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

# DEAD CONTENT on a live role: this grants s3:* on a bucket named
# "tpp-numeriseur" which does not exist in this account.
resource "aws_iam_policy" "tpp_numeriseur" {
  name = "tpp-numeriseur"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "Stmt1509547202000"
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["arn:aws:s3:::tpp-numeriseur", "arn:aws:s3:::tpp-numeriseur/*"]
    }]
  })
}

# DEAD CONTENT on a live role: hosted zone Z2JK7DWF2FL0X9 no longer exists
# (confirmed NoSuchHostedZone). The only zone in this account is shrt.example,
# Z3763GCGZU6IDP.
resource "aws_iam_policy" "tpp_numeriseur_route53" {
  name = "tpp-numeriseur-route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Stmt1509574126000"
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = ["arn:aws:route53:::hostedzone/Z2JK7DWF2FL0X9", "arn:aws:route53:::change/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones"]
        Resource = ["*"]
      },
    ]
  })
}

# DEAD CONTENT on a live role: vol-0aaaaaaaaaaaaaaa2 does not exist. The only
# volume in the account is the running node's root.
resource "aws_iam_policy" "strategie_docs_numeriseur" {
  name = "StrategieDocsNumeriseur"
  # Verbatim from the live policy: description is immutable in the IAM API
  # (ForceNew), so omitting it planned a replace of policy + attachments.
  description = "Permet dattacher un volume EBS avec documents numerises"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "VisualEditor0"
      Effect   = "Allow"
      Action   = "ec2:AttachVolume"
      Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:volume/vol-0aaaaaaaaaaaaaaa2"]
    }]
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

resource "aws_iam_role_policy_attachment" "aws_node_numeriseur" {
  role       = aws_iam_role.aws_node.name
  policy_arn = aws_iam_policy.tpp_numeriseur.arn
}

resource "aws_iam_role_policy_attachment" "aws_node_route53" {
  role       = aws_iam_role.aws_node.name
  policy_arn = aws_iam_policy.tpp_numeriseur_route53.arn
}

resource "aws_iam_role_policy_attachment" "aws_node_docs" {
  role       = aws_iam_role.aws_node.name
  policy_arn = aws_iam_policy.strategie_docs_numeriseur.arn
}

# --- RoleBackup: PrendreInstantanes + PurgerInstantanes lambdas ------------
#
# Both lambdas still run python2.7, a runtime AWS retired years ago. They keep
# executing but cannot be updated in place. That is a phase 6 problem.

resource "aws_iam_role" "backup" {
  name = "RoleBackup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "backup_snapshots" {
  name = "PrendreInstantanes"
  role = aws_iam_role.backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = "ec2:Describe*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CreateTags",
          "ec2:ModifySnapshotAttribute",
          "ec2:ResetSnapshotAttribute",
        ]
        Resource = ["*"]
      },
    ]
  })
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
# no consumer. Both now grant nothing.
#
# STILL PRESENT IN THE ACCOUNT — the objects themselves have not been deleted
# yet, so this file no longer describes them and they are currently unmanaged:
#
#   roles      ecsInstanceRole, RoleAdmin, RoleOrchestre, RoleBastion,
#              RolePorteCles, RoleSonde, RoleS3Admin, RoleGestionSSM
#   profiles   the same seven names (RoleGestionSSM has none)
#   policies   policygen-201710221013, policygen-201711011046,
#              policygen-201711011810, strategie-portecles-1,
#              terraform-policy,
#              AWSLambdaBasicExecutionRole-b4e12542-… (/service-role/ path)
#   group      administrateurs (empty, grants AdministratorAccess)
#
# The deletion commands are in the README under "Finishing the phase 4
# cleanup". Until they are run, the above exists in AWS but in no state file.
# Everything needed to recreate it is in commit 31185bd if that turns out to
# have been a mistake.
#
# ALSO STILL OUTSTANDING — three policies remain attached to the live RoleAws
# and all three reference resources that no longer exist:
#   tpp-numeriseur          (bucket does not exist)
#   tpp-numeriseur-route53  (hosted zone Z2JK7DWF2FL0X9 — NoSuchHostedZone)
#   StrategieDocsNumeriseur (volume vol-0aaaaaaaaaaaaaaa2)
# They are still declared above because they are still attached. Detaching them
# is safe — they grant nothing reachable — but it changes a live role, so it is
# deliberately not bundled with the dead-role cleanup.
#
# Deliberately NOT touched:
#   tpp-aws-s3-full  — broad but load-bearing; narrowing it is its own project
#   ludorl82         — the account's only human identity
#   RoleBackup       — last used 2023-11-12, but still wired to two lambdas;
#                      it and they are phase 6's problem, not this file's
