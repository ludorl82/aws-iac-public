# Import blocks for phase 3: S3 buckets and the pipeline IAM users.
#
# Sub-resources of a bucket are imported by BUCKET NAME, not by any composite
# id — aws_s3_bucket_versioning, _public_access_block, _lifecycle_configuration
# and friends all take the bare bucket name.

# --- buckets ---------------------------------------------------------------

import {
  to = aws_s3_bucket.backups_portecles
  id = "backups-portecles-example-com"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.backups_portecles
  id = "backups-portecles-example-com"
}

import {
  to = aws_s3_bucket_public_access_block.backups_portecles
  id = "backups-portecles-example-com"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.backups_portecles
  id = "backups-portecles-example-com"
}

import {
  to = aws_s3_bucket.frigate_snapshots
  id = "frigate-snapshots-example-com"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.frigate_snapshots
  id = "frigate-snapshots-example-com"
}

import {
  to = aws_s3_bucket_public_access_block.frigate_snapshots
  id = "frigate-snapshots-example-com"
}

import {
  to = aws_s3_bucket_ownership_controls.frigate_snapshots
  id = "frigate-snapshots-example-com"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.frigate_snapshots
  id = "frigate-snapshots-example-com"
}

import {
  to = aws_s3_bucket.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket_versioning.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket_public_access_block.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket_ownership_controls.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket_lifecycle_configuration.homelab_backups
  id = "homelab-backups-example-com"
}

import {
  to = aws_s3_bucket.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket_public_access_block.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket_ownership_controls.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket_website_configuration.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket_policy.labodeludo
  id = "labodeludo.dev"
}

import {
  to = aws_s3_bucket.loki_logs
  id = "loki-logs-example-com"
}

import {
  to = aws_s3_bucket_versioning.loki_logs
  id = "loki-logs-example-com"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.loki_logs
  id = "loki-logs-example-com"
}

import {
  to = aws_s3_bucket_public_access_block.loki_logs
  id = "loki-logs-example-com"
}

import {
  to = aws_s3_bucket_ownership_controls.loki_logs
  id = "loki-logs-example-com"
}

import {
  to = aws_s3_bucket.shrt_example
  id = "shrt.example"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.shrt_example
  id = "shrt.example"
}

import {
  to = aws_s3_bucket_website_configuration.shrt_example
  id = "shrt.example"
}

import {
  to = aws_s3_bucket.mkv_plex
  id = "mkv.plex.lab.example"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.mkv_plex
  id = "mkv.plex.lab.example"
}

import {
  to = aws_s3_bucket_public_access_block.mkv_plex
  id = "mkv.plex.lab.example"
}

import {
  to = aws_s3_bucket_ownership_controls.mkv_plex
  id = "mkv.plex.lab.example"
}

# us-east-1 — the import block inherits the provider from the target resource,
# so no extra plumbing is needed here beyond the alias on the resource itself.
import {
  to = aws_s3_bucket.numeriseur_scans
  id = "numeriseur-scans-example-com"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.numeriseur_scans
  id = "numeriseur-scans-example-com"
}

import {
  to = aws_s3_bucket_public_access_block.numeriseur_scans
  id = "numeriseur-scans-example-com"
}

import {
  to = aws_s3_bucket_ownership_controls.numeriseur_scans
  id = "numeriseur-scans-example-com"
}

# --- IAM -------------------------------------------------------------------
#
# aws_iam_user_policy imports as "user:policy-name".
# aws_iam_user_policy_attachment imports as "user/policy-arn".

import {
  to = aws_iam_user.labodeludo_deploy
  id = "labodeludo-deploy"
}

import {
  to = aws_iam_user_policy.labodeludo_deploy
  id = "labodeludo-deploy:labodeludo-s3-deploy"
}

import {
  to = aws_iam_user.loki_s3
  id = "loki-s3"
}

import {
  to = aws_iam_user_policy.loki_s3
  id = "loki-s3:loki-s3-bucket-only"
}

import {
  to = aws_iam_user.svc_numeriseur
  id = "svc-numeriseur"
}

import {
  to = aws_iam_user_policy.svc_numeriseur
  id = "svc-numeriseur:numeriseur-scans-bucket"
}

import {
  to = aws_iam_user.docker_homelab_backup
  id = "docker-homelab-backup"
}

import {
  to = aws_iam_policy.homelab_backup_docker_write
  id = "arn:aws:iam::123456789012:policy/homelab-backup-docker-write"
}

import {
  to = aws_iam_user_policy_attachment.docker_homelab_backup
  id = "docker-homelab-backup/arn:aws:iam::123456789012:policy/homelab-backup-docker-write"
}

import {
  to = aws_iam_user.pi-02_homelab_backup
  id = "pi-02-homelab-backup"
}

import {
  to = aws_iam_policy.homelab_backup_pi-02_write
  id = "arn:aws:iam::123456789012:policy/homelab-backup-pi-02-write"
}

import {
  to = aws_iam_user_policy_attachment.pi-02_homelab_backup
  id = "pi-02-homelab-backup/arn:aws:iam::123456789012:policy/homelab-backup-pi-02-write"
}
