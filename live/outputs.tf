output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
  value = {
    ca-central-1a = aws_subnet.a.id
    ca-central-1b = aws_subnet.b.id
  }
}

output "security_group_main_id" {
  value = aws_security_group.main.id
}

output "aws_node_public_ip" {
  value = aws_eip.aws_node.public_ip
}

output "bucket_names" {
  value = {
    backups_portecles = aws_s3_bucket.backups_portecles.id
    frigate_snapshots = aws_s3_bucket.frigate_snapshots.id
    homelab_backups   = aws_s3_bucket.homelab_backups.id
    labodeludo        = aws_s3_bucket.labodeludo.id
    loki_logs         = aws_s3_bucket.loki_logs.id
    shrt_example      = aws_s3_bucket.shrt_example.id
    mkv_plex          = aws_s3_bucket.mkv_plex.id
    numeriseur_scans  = aws_s3_bucket.numeriseur_scans.id
  }
}
