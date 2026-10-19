provider "aws" {
  region = "ca-central-1"

  # Guard against ever pointing this root at the wrong account.
  allowed_account_ids = ["123456789012"]

  default_tags {
    tags = {
      ManagedBy = "opentofu"
      Repo      = "aws-iac"
      Root      = "live"
    }
  }
}

# us-east-1 exists for exactly one reason: ACM certificates used by CloudFront
# must live there (the shrt.example cert, phase 5). Nothing else belongs in this
# provider — new resources go in the default region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  allowed_account_ids = ["123456789012"]

  default_tags {
    tags = {
      ManagedBy = "opentofu"
      Repo      = "aws-iac"
      Root      = "live"
    }
  }
}
