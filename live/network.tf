# Phase 2: VPC, subnets, gateway, routing, security groups, EIP.
#
# Every attribute below was read off the live account, so the only diff on the
# first apply should be default_tags being added. Anything else in that plan is
# a bug in this file — fix the file, not the account.

resource "aws_vpc" "main" {
  cidr_block                       = "198.51.100.0/24"
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true
  instance_tenancy                 = "default"

  tags = {
    Name = "vpc"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "router-internet"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ca-central-1a — holds the live node (198.51.100.7 / cloud-01.example.com).
resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "198.51.100.0/24"
  availability_zone = "ca-central-1a"
  # 16 = 0x10: the /64 index matches the hex-of-last-octet convention
  # (198.51.100.0/24 -> ...:e810::/64). HCL has no hex literals, hence decimal.
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 16)

  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  private_dns_hostname_type_on_launch = "resource-name"

  tags = {
    Name = "sous-reseau-1"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ca-central-1b — empty since the master node was decommissioned. Kept because
# a second AZ costs nothing and losing it is a VPC-level change.
#
# Note the drift from subnet "a": IPv6-on-creation is enabled here and the
# hostname type is ip-name. That asymmetry is real, not a typo — it is what the
# account has. Normalise it deliberately later if you want, in its own commit.
resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "203.0.113.0/24"
  availability_zone = "ca-central-1b"
  # 32 = 0x20 (203.0.113.0/24 -> ...:e820::/64), same convention as subnet a.
  ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 32)

  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = true

  private_dns_hostname_type_on_launch = "ip-name"

  tags = {
    Name = "aws2-subnet"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The VPC's main route table, dual-stack default out through the IGW.
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name = "principal"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_default_route_table.main.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_default_route_table.main.id
}

# Unused by design — nothing should ever be attached to it. Declaring it empty
# is what keeps it that way; AWS will not let you delete a VPC's default SG.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  ingress {
    protocol  = "-1"
    from_port = 0
    to_port   = 0
    self      = true
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "default-unused"
  }
}

locals {
  vpc_cidr = "198.51.100.0/24"

  # Home WAN address. This changes; when it does, the SSH rule below is what
  # locks you out. router already runs a WAN-IP sync cron for Cloudflare —
  # this is the second consumer of that value.
  home_ipv4 = "192.0.2.1/32"

  home_ipv6 = [
    "2001:db8:50:a::/64",      # WAN
    "2001:db8:8702:f309::/64", # LAN
  ]
}

resource "aws_security_group" "main" {
  name        = "aws-main"
  description = "Main security group for aws instance"
  vpc_id      = aws_vpc.main.id

  # --- k3s control plane / cluster mesh, VPC-internal only ---
  ingress {
    description = "k3s apiserver"
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "k3s supervisor"
    protocol    = "tcp"
    from_port   = 9345
    to_port     = 9345
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "etcd peer + client"
    protocol    = "tcp"
    from_port   = 2379
    to_port     = 2380
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "kubelet"
    protocol    = "tcp"
    from_port   = 10250
    to_port     = 10250
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "flannel vxlan"
    protocol    = "udp"
    from_port   = 8472
    to_port     = 8472
    cidr_blocks = [local.vpc_cidr]
  }

  # --- application ingress, VPC-internal only ---
  #
  # These are deliberately not open to the internet. Public reach happens
  # through the Cloudflare tunnel, never through this SG. See the account note:
  # opening 80/443 here as a shortcut is the thing not to do.
  ingress {
    description = "HTTP - VPC-internal EC2 nodes"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Traefik ingress - VPC-internalEC2 nodes"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Kuma push - VPC-internal EC2 nodes"
    protocol    = "tcp"
    from_port   = 3001
    to_port     = 3001
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "Loki push - VPC-internal EC2 nodes"
    protocol    = "tcp"
    from_port   = 3100
    to_port     = 3100
    cidr_blocks = [local.vpc_cidr]
  }

  # --- administrative ---
  ingress {
    description      = "SSH from home"
    protocol         = "tcp"
    from_port        = 22
    to_port          = 22
    cidr_blocks      = [local.home_ipv4]
    ipv6_cidr_blocks = local.home_ipv6
  }

  ingress {
    description = "WireGuard"
    protocol    = "udp"
    from_port   = 51820
    to_port     = 51820
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Required by IPv6 PMTUD and NDP — do not narrow this to echo only.
  ingress {
    description      = "ICMPv6"
    protocol         = "icmpv6"
    from_port        = -1
    to_port          = -1
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "aws-main"
  }
}

# The public IP of cloud-01.example.com. Releasing this is unrecoverable and it is
# baked into DNS, WireGuard peers and the Cloudflare tunnel — hence the guard.
resource "aws_eip" "aws_node" {
  domain   = "vpc"
  instance = aws_instance.aws_node.id

  tags = {
    Name = "cloud-01.example.com"
  }

  lifecycle {
    prevent_destroy = true
  }
}
