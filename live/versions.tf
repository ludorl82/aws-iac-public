terraform {
  # use_lockfile (native S3 state locking, no DynamoDB table) needs OpenTofu
  # 1.10+. If you pin something older, you must reintroduce a lock table.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
