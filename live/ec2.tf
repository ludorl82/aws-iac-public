# Phase 6a: the one EC2 instance — cloud-01.example.com, k3s control plane,
# NixOS (converted 2026-07-25 via kexec/nixos-anywhere).
#
# Scope boundary applies hard here: this describes only the AWS-side shell.
# The OS inside has nothing to do with the AMI below — that is the long-dead
# image the instance originally booted from, kept because ami is ForceNew and
# the running root filesystem was replaced in place by nixos-anywhere.
# Everything OS-level lives in nixos-iac.

resource "aws_instance" "aws_node" {
  ami           = "ami-06099a0bfaf3b7919"
  instance_type = "t3a.medium"

  availability_zone = "ca-central-1a"
  subnet_id         = aws_subnet.a.id
  private_ip        = "198.51.100.7"

  # ::7 matches the hex-of-last-octet convention (198.51.100.7).
  ipv6_addresses      = ["2001:db8:100:10::7"]
  enable_primary_ipv6 = true

  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile   = aws_iam_instance_profile.aws_node.name
  key_name               = "example-keypair"

  ebs_optimized           = true
  disable_api_termination = true

  credit_specification {
    cpu_credits = "unlimited"
  }

  # IMDSv2 enforced — http_tokens=required is deliberate, keep it that way.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # delete_on_termination=false is the load-bearing bit: the root volume
  # survives instance termination (it did exactly that during the July EIP
  # resize dance).
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 64
    iops                  = 3000
    throughput            = 125
    delete_on_termination = false
    encrypted             = false

    tags = {
      Name = "aws1-root-64g-new"
    }
  }

  tags = {
    Name = "cloud-01.example.com"
  }

  lifecycle {
    prevent_destroy = true
  }
}
