# Phase 4: the remaining IAM — roles, instance profiles, customer-managed
# policies, the admin user and the admin group.
#
# This file now describes only what has a live consumer. The dead half was
# adopted first (commit 31185bd) and removed here, deliberately in that order:
# doing the import and the cleanup in one step makes "I broke it" and "the
# import was wrong" indistinguishable when something stops working.
#
# The account-side deletions are NOT all done — see the CLEANUP section at the
# bottom for exactly what still exists in AWS but is no longer described here.
#
# The pipeline users and their two policies live in iam-pipelines.tf (phase 3).

# ===========================================================================
# LIVE — these have a consumer today
# ===========================================================================

# --- RoleAws: the running EC2 instance (cloud-01.example.com) ----------------

resource "aws_iam_role" "aws_node" {
  name = "RoleAws"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "aws_node" {
  name = "RoleAws"
  role = aws_iam_role.aws_node.name
}

# Grants s3:CreateBucket and s3:* on every bucket in the account. Broad, and
# the reason the KeePass backup cron and the Frigate snapshot pipeline both
# work without per-bucket grants. Narrowing it is a real project, not a tidy-up.
resource "aws_iam_policy" "tpp_aws_s3_full" {
  name = "tpp-aws-s3-full"
  # Verbatim from the live policy: description is immutable in the IAM API
  # (ForceNew), so omitting it planned a replace of policy + attachments.
  description = "Create and fully access/write any S3 bucket in the account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateAnyBucket"
        Effect   = "Allow"
        Action   = "s3:CreateBucket"
        Resource = "*"
      },
      {
        Sid      = "FullAccessAnyBucket"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = ["arn:aws:s3:::*", "arn:aws:s3:::*/*"]
      },
    ]
  })
}

resource "aws_iam_policy" "tpp_numeriseur_keepass_backups" {
  name = "tpp-numeriseur-keepass-backups"
  # Verbatim from the live policy: description is immutable in the IAM API
  # (ForceNew), so omitting it planned a replace of policy + attachments.
  description = "Allow RoleNumeriseur to write daily KeePass backups (keepass2_*) to backups-portecles-example-com"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutKeepassBackups"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::backups-portecles-example-com/keepass2_*"
      },
      {
        Sid       = "ListBackupsBucketKeepassPrefix"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = "arn:aws:s3:::backups-portecles-example-com"
        Condition = { StringLike = { "s3:prefix" = ["keepass2_*"] } }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_node_s3_full" {
  role       = aws_iam_role.aws_node.name
  policy_arn = aws_iam_policy.tpp_aws_s3_full.arn
}

resource "aws_iam_role_policy_attachment" "aws_node_keepass" {
  role       = aws_iam_role.aws_node.name
  policy_arn = aws_iam_policy.tpp_numeriseur_keepass_backups.arn
}

# --- RoleCloudFrontIps: AjouterIpsCloudfront lambda ------------------------
#
# Keeps a security group's ingress in sync with CloudFront's published ranges.

resource "aws_iam_role" "cloudfront_ips" {
  name = "RoleCloudFrontIps"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "tpp_cloudfront_ips" {
  name = "tpp-cloudfront-ips"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:ca-central-1:123456789012:security-group/*"
      },
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeSecurityGroups"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudfront_ips" {
  role       = aws_iam_role.cloudfront_ips.name
  policy_arn = aws_iam_policy.tpp_cloudfront_ips.arn
}

# --- short_url_lambda_iam: add_object_url + del_object_url (shrt.example) --------

resource "aws_iam_role" "short_url_lambda" {
  name = "short_url_lambda_iam"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_policy" "short_url_s3" {
  name = "short_url_s3_policy"
  # Verbatim from the live policy: description is immutable in the IAM API
  # (ForceNew), so omitting it planned a replace of policy + attachments.
  description = "Short URL S3 policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObjectAcl",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:PutObjectAcl",
      ]
      # Note the first ARN has a stray trailing slash — "shrt.example/" is not the
      # bucket ARN, so s3:ListBucket here effectively does nothing. Left as-is;
      # the lambdas work, so nothing depends on that statement being correct.
      Resource = ["arn:aws:s3:::shrt.example/", "arn:aws:s3:::shrt.example/*"]
    }]
  })
}

resource "aws_iam_policy" "short_url_ssm" {
  name = "short_url_ssm_policy"
  # Verbatim from the live policy: description is immutable in the IAM API
  # (ForceNew), so omitting it planned a replace of policy + attachments.
  description = "Short URL SSM policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "short_url_s3" {
  role       = aws_iam_role.short_url_lambda.name
  policy_arn = aws_iam_policy.short_url_s3.arn
}

resource "aws_iam_role_policy_attachment" "short_url_ssm" {
  role       = aws_iam_role.short_url_lambda.name
  policy_arn = aws_iam_policy.short_url_ssm.arn
}

# --- the human admin -------------------------------------------------------
#
# This user's access key (created 2025-05-10) is not managed here for the same
# reason the pipeline keys are not: it would land in state in plain text. It is
# also the credential every plan in this repo currently runs as — see the
# README note about moving to a dedicated assumed role.
#
#   aws iam list-access-keys --user-name ludorl82

resource "aws_iam_user" "ludorl82" {
  name = "ludorl82"
}

resource "aws_iam_user_policy_attachment" "ludorl82_admin" {
  user       = aws_iam_user.ludorl82.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ===========================================================================
# CLEANUP — what was removed, and what is still outstanding
# ===========================================================================
#
# DONE 2026-07-25: the managed-policy attachments on the eight dead roles were
# detached, which is the part that actually mattered — RoleAdmin and
# RoleOrchestre each carried AdministratorAccess on an EC2-assumable role with
# no consumer. Both then granted nothing.
#
# DONE (verified 2026-07-27): the objects themselves were deleted from the
# account (the eight roles, their seven instance profiles, the six orphaned
# policies, the empty administrateurs group). Everything needed to recreate
# them is in commit 31185bd if that turns out to have been a mistake.
#
# DONE 2026-07-27: the three dead-reference policies that were still attached
# to the live RoleAws (tpp-numeriseur, tpp-numeriseur-route53,
# StrategieDocsNumeriseur) were removed from this file and destroyed via
# apply. Same day, RoleBackup and the python2.7 snapshot lambdas it served
# went too — see lambdas.tf.
#
# Deliberately NOT touched:
#   tpp-aws-s3-full  — broad but load-bearing; narrowing it is its own project
#   ludorl82         — the account's only human identity
