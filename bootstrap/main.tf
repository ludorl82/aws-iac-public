# Bootstrap: the S3 bucket that holds every other state file.
#
# This root uses LOCAL state on purpose — a state backend cannot store its own
# state without a chicken-and-egg problem. The local state is gitignored and
# deliberately disposable: if you lose it, recreate it with
#
#   tofu import aws_s3_bucket.tfstate tfstate-example-com
#
# Nothing here is precious except the bucket itself, which is why it carries
# prevent_destroy and versioning.

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "ca-central-1"

  default_tags {
    tags = {
      ManagedBy = "opentofu"
      Repo      = "aws-iac"
      Root      = "bootstrap"
    }
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-example-com"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State files accumulate noninfinitely but pointlessly; keep the last 90 days of
# versions so a bad apply is recoverable without the bucket growing forever.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "bucket" {
  value = aws_s3_bucket.tfstate.id
}
