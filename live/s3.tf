# Phase 3a: S3 buckets.
#
# Sub-resource blocks are only declared where the live bucket actually has that
# configuration. Where a bucket has never had (say) ownership controls set, the
# resource is omitted rather than declared with defaults — declaring it would be
# a real change to the account, not an adoption.
#
# Bucket VERSIONING is the sharpest edge here: aws_s3_bucket_versioning is
# omitted for buckets that were never versioned, because "Disabled" is a
# write-once state that cannot be returned to once you enable or suspend.

# ---------------------------------------------------------------------------
# backups-portecles-example-com — KeePass backups (aws cron -> S3, 01:05)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "backups_portecles" {
  bucket = "backups-portecles-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups_portecles" {
  bucket = aws_s3_bucket.backups_portecles.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "backups_portecles" {
  bucket = aws_s3_bucket.backups_portecles.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups_portecles" {
  bucket = aws_s3_bucket.backups_portecles.id

  rule {
    id     = "expire-keepass-backups-365d"
    status = "Enabled"

    filter {
      prefix = "keepass2_"
    }

    expiration {
      days = 365
    }
  }
}

# ---------------------------------------------------------------------------
# frigate-snapshots-example-com — nas -> aws -> S3
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "frigate_snapshots" {
  bucket = "frigate-snapshots-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frigate_snapshots" {
  bucket = aws_s3_bucket.frigate_snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "frigate_snapshots" {
  bucket = aws_s3_bucket.frigate_snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frigate_snapshots" {
  bucket = aws_s3_bucket.frigate_snapshots.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Retention is per-prefix: stills kept a year, low-res clips only 3 days.
# The prefixes are camera-specific — adding a camera means adding a rule.
resource "aws_s3_bucket_lifecycle_configuration" "frigate_snapshots" {
  bucket = aws_s3_bucket.frigate_snapshots.id

  rule {
    id     = "expire-snapshots-after-1-year"
    status = "Enabled"

    filter {
      prefix = "ad410-avant/"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "expire-lowres-video-after-3-days"
    status = "Enabled"

    filter {
      prefix = "ad410-avant-lowres/"
    }

    expiration {
      days = 3
    }
  }
}

# ---------------------------------------------------------------------------
# homelab-backups-example-com — per-service backups from docker + pi-02
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "homelab_backups" {
  bucket = "homelab-backups-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 30-day retention on a versioned bucket. Note this is the whole bucket, every
# prefix — a backup older than 30 days does not exist anywhere in this account.
resource "aws_s3_bucket_lifecycle_configuration" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ---------------------------------------------------------------------------
# labodeludo.dev — public static site origin (Astro build output)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "labodeludo" {
  bucket = "labodeludo.dev"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "labodeludo" {
  bucket = aws_s3_bucket.labodeludo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# Deliberately all-false: this bucket serves the public site and the policy
# below depends on public policies being permitted. Do not "harden" this to
# true without first moving the site behind an origin access identity.
resource "aws_s3_bucket_public_access_block" "labodeludo" {
  bucket = aws_s3_bucket.labodeludo.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "labodeludo" {
  bucket = aws_s3_bucket.labodeludo.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_website_configuration" "labodeludo" {
  bucket = aws_s3_bucket.labodeludo.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_policy" "labodeludo" {
  bucket = aws_s3_bucket.labodeludo.id
  policy = data.aws_iam_policy_document.labodeludo_public_read.json

  # The public access block must be settled before a public policy is accepted.
  depends_on = [aws_s3_bucket_public_access_block.labodeludo]
}

data "aws_iam_policy_document" "labodeludo_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.labodeludo.arn}/*"]
  }
}

# ---------------------------------------------------------------------------
# loki-logs-example-com — Loki chunk store (logging namespace on gpu-01)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "loki_logs" {
  bucket = "loki-logs-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

# Suspended, not absent — versioning was enabled here at some point and turned
# back off. Keep it declared so it cannot silently drift back to Enabled.
resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# shrt.example — short-URL store behind CloudFront EWDRKSTHXOKI7
# ---------------------------------------------------------------------------
#
# This bucket has NO public access block and NO ownership controls. That is the
# live state and it is load-bearing for how the short_url lambdas write objects,
# so both resources are omitted rather than adopted-with-defaults. Revisit in
# phase 5 alongside the CloudFront distribution, not before.

resource "aws_s3_bucket" "shrt_example" {
  bucket = "shrt.example"

  tags = {
    Project = "short_urls"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "shrt_example" {
  bucket = aws_s3_bucket.shrt_example.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# Non-obvious: the index suffix is "web" and the error key is "error", not
# index.html / error.html. The short-URL redirect objects are named accordingly.
resource "aws_s3_bucket_website_configuration" "shrt_example" {
  bucket = aws_s3_bucket.shrt_example.id

  index_document {
    suffix = "web"
  }

  error_document {
    key = "error"
  }
}

# ---------------------------------------------------------------------------
# mkv.plex.lab.example — Plex media staging
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "mkv_plex" {
  bucket = "mkv.plex.lab.example"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mkv_plex" {
  bucket = aws_s3_bucket.mkv_plex.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # The only bucket in the account with S3 Bucket Keys on.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "mkv_plex" {
  bucket = aws_s3_bucket.mkv_plex.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "mkv_plex" {
  bucket = aws_s3_bucket.mkv_plex.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# numeriseur-scans-example-com — scanner output (SFTPGo -> S3)
# ---------------------------------------------------------------------------
#
# Migrated from us-east-1 to ca-central-1 on 2026-07-25, keeping this name.
#
# A bucket's region is immutable and names are globally unique, so moving region
# means delete-and-recreate. AWS then held the name for roughly an hour after
# the delete (CreateBucket returning OperationAborted, with no way to check or
# hurry it), so the bucket ran temporarily as numeriseur-scans-ca-example-com
# until the original freed up and was reclaimed. If you ever do this again:
# create the new bucket FIRST, cut over, and delete the old one afterwards —
# the delete-first ordering buys nothing and costs an outage of unbounded
# length.
#
# Consumers that had to change with it: the SFTPGo image (bucket was hardcoded
# in its users.json template and post-upload.sh; now the S3_BUCKET env var) and
# the svc-numeriseur inline IAM policy below.

resource "aws_s3_bucket" "numeriseur_scans" {
  bucket = "numeriseur-scans-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "numeriseur_scans" {
  bucket = aws_s3_bucket.numeriseur_scans.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "numeriseur_scans" {
  bucket = aws_s3_bucket.numeriseur_scans.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "numeriseur_scans" {
  bucket = aws_s3_bucket.numeriseur_scans.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
