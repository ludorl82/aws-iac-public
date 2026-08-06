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
#
# ONE exception, added deliberately rather than by adoption:
# backups_portecles had versioning enabled on 2026-08-05 as the prerequisite
# for Object Lock. Two backup buckets are now locked (GOVERNANCE, 30 days) so
# the credential that writes a backup can no longer delete it. Two rules
# follow from that and are easy to get wrong:
#
#   - Lock retention must stay SHORTER than any expiration rule on the same
#     bucket, or lifecycle silently stops reclaiming.
#   - Any versioned bucket with an expiration rule also needs a noncurrent
#     rule, or `expiration` just writes delete markers over versions that are
#     never reaped.

# ---------------------------------------------------------------------------
# backups-portecles-example-com — KeePass backups (aws cron -> S3, 01:05)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "backups_portecles" {
  bucket = "backups-portecles-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

# TWO ONE-WAY DOORS, both opened deliberately on 2026-08-05.
#
# 1. Versioning. This bucket had never been versioned, and "never versioned"
#    is a state you cannot return to — from here it can only be Enabled or
#    Suspended. It is enabled because Object Lock requires it.
# 2. Object Lock, below, cannot be disabled once on, and versioning can never
#    be suspended afterwards.
#
# The reason to accept both: the credential that writes these backups could
# also delete them. This bucket holds the KeePass vault backups — the one
# dataset here that is genuinely irreplaceable.
resource "aws_s3_bucket_versioning" "backups_portecles" {
  bucket = aws_s3_bucket.backups_portecles.id

  versioning_configuration {
    status = "Enabled"
  }
}

# GOVERNANCE, not COMPLIANCE. Compliance mode cannot be shortened or removed
# by anyone including the root account — the only escape is deleting the AWS
# account. That is the correct trade for a regulated archive and the wrong one
# for a homelab, where the likeliest reason to break the lock is my own
# mistake. Governance keeps the protection and leaves a scoped
# s3:BypassGovernanceRetention escape hatch.
#
# 30 days: long enough that a bad delete is still recoverable when it is
# noticed, and far short of the 365-day keepass2_ lifecycle below, so the
# expiry rule keeps working. Retention must always stay under the expiration
# it shares a bucket with, or lifecycle silently stops reclaiming.
resource "aws_s3_bucket_object_lock_configuration" "backups_portecles" {
  bucket = aws_s3_bucket.backups_portecles.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }

  # Object Lock is rejected outright unless versioning is already on.
  depends_on = [aws_s3_bucket_versioning.backups_portecles]
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

  # The noncurrent rule is NOT decoration — it is required now that the bucket
  # is versioned. On an unversioned bucket `expiration` permanently deleted the
  # object. On a versioned one it only writes a delete marker, and the version
  # underneath becomes noncurrent and stays forever unless something reaps it.
  # Enabling versioning without this line would have quietly converted a
  # working 365-day expiry into unbounded growth.
  #
  # 30 days matches the lock retention: a version can only be reclaimed once
  # its retention has expired, so anything shorter would be refused. Equal is
  # fine — S3 retries on later lifecycle runs, so a version caught exactly on
  # the boundary is reclaimed a day late rather than never.
  rule {
    id     = "expire-keepass-backups-365d"
    status = "Enabled"

    filter {
      prefix = "keepass2_"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------------------------------------------------------------------------
# deadman-example-com — dead-man switch heartbeats (see deadman.tf)
# ---------------------------------------------------------------------------
#
# Split out of homelab-backups on 2026-08-05, so that bucket can take Object
# Lock. The two heartbeats are overwritten every 5 minutes, and a WORM bucket
# cannot host a 5-minute overwrite loop: Object Lock makes a permanent version
# delete return 403, so noncurrent-version expiry silently stops reclaiming
# them and locked versions pile up for the whole retention period.
#
# So this bucket is deliberately the opposite of a backup bucket:
# NOT versioned, NOT locked, no lifecycle rule. Only four keys ever exist
# (two heartbeats, two .alerted/ markers) and every write overwrites in place,
# so there is nothing to expire. Do not "harden" this by enabling versioning —
# that is the exact thing this split exists to avoid.
#
# Contents are worthless: a timestamp, rewritten every 5 minutes. What matters
# is the WRITE, not the data.

resource "aws_s3_bucket" "deadman" {
  bucket = "deadman-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deadman" {
  bucket = aws_s3_bucket.deadman.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "deadman" {
  bucket = aws_s3_bucket.deadman.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "deadman" {
  bucket = aws_s3_bucket.deadman.id

  rule {
    object_ownership = "BucketOwnerEnforced"
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

# Already versioned, so only the lock itself is new here. Same reasoning as
# backups_portecles: GOVERNANCE 30 days, with a scoped bypass rather than
# compliance mode.
#
# This bucket is only eligible because the dead-man heartbeats moved out on
# 2026-08-05 (see the deadman bucket above). They overwrote the same key every
# 5 minutes, and locked versions cannot be reclaimed by lifecycle — they would
# have accumulated for the full retention instead of being reaped at 7 days.
resource "aws_s3_bucket_object_lock_configuration" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.homelab_backups]
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
#
# noncurrent raised 7 -> 30 on 2026-08-05 to match the Object Lock retention
# above. A version under retention cannot be permanently deleted, so a 7-day
# rule against a 30-day lock would have been refused for three weeks out of
# every four — a lifecycle rule that looks configured and quietly does nothing,
# which is the failure mode worth avoiding here.
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
      noncurrent_days = 30
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
