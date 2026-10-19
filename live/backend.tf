terraform {
  backend "s3" {
    bucket = "tfstate-example-com"
    key    = "live/terraform.tfstate"
    region = "ca-central-1"

    encrypt = true

    # Native S3 conditional-write locking. Replaces the old DynamoDB lock table
    # entirely — do not add dynamodb_table alongside this.
    use_lockfile = true
  }
}
