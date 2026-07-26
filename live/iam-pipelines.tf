# Phase 3b: the IAM users behind the data pipelines.
#
# ACCESS KEYS ARE NOT MANAGED HERE, deliberately. aws_iam_access_key writes the
# secret into state in plaintext, which would turn the state bucket into a
# credential store. Each of these five users has one key, created out of band
# between 2026-07-07 and 2026-07-18 and stored in KeePass; rotating one means
# creating it by hand and updating the consumer.
#
# Key IDs are deliberately not listed here — the pre-commit hook treats an
# AKIA… literal as a secret, and they are one command away anyway:
#
#   aws iam list-access-keys --user-name <user>
#
# The human user `ludorl82` (AdministratorAccess) is in iam.tf with the rest of
# phase 4 — it is not a pipeline identity.

# ---------------------------------------------------------------------------
# iac-drift — nightly drift detection (k3s CronJob, k3s-iac/iac-drift/)
# ---------------------------------------------------------------------------
#
# Runs `tofu plan -detailed-exitcode -lock=false` against this very config.
# ReadOnlyAccess covers every provider read plus the state object in S3;
# -lock=false means it never needs a single write permission. Access key is
# out-of-band like the rest (k8s Secret iac-drift-aws in the iac-drift ns).

resource "aws_iam_user" "iac_drift" {
  name = "iac-drift"
}

resource "aws_iam_user_policy_attachment" "iac_drift_readonly" {
  user       = aws_iam_user.iac_drift.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# labodeludo-deploy — CI pushes the Astro build to the site bucket
# ---------------------------------------------------------------------------

resource "aws_iam_user" "labodeludo_deploy" {
  name = "labodeludo-deploy"
}

data "aws_iam_policy_document" "labodeludo_deploy" {
  statement {
    sid       = "ListBucketOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.labodeludo.arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.labodeludo.arn}/*"]
  }
}

resource "aws_iam_user_policy" "labodeludo_deploy" {
  name   = "labodeludo-s3-deploy"
  user   = aws_iam_user.labodeludo_deploy.name
  policy = data.aws_iam_policy_document.labodeludo_deploy.json
}

# ---------------------------------------------------------------------------
# loki-s3 — Loki chunk/index writes from the logging namespace
# ---------------------------------------------------------------------------

resource "aws_iam_user" "loki_s3" {
  name = "loki-s3"
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    sid       = "LokiBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.loki_logs.arn]
  }

  statement {
    sid    = "LokiObjectRW"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.loki_logs.arn}/*"]
  }
}

resource "aws_iam_user_policy" "loki_s3" {
  name   = "loki-s3-bucket-only"
  user   = aws_iam_user.loki_s3.name
  policy = data.aws_iam_policy_document.loki_s3.json
}

# ---------------------------------------------------------------------------
# svc-numeriseur — scanner output via SFTPGo
# ---------------------------------------------------------------------------

resource "aws_iam_user" "svc_numeriseur" {
  name = "svc-numeriseur"
}

data "aws_iam_policy_document" "svc_numeriseur" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.numeriseur_scans.arn]
  }

  statement {
    sid    = "ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.numeriseur_scans.arn}/*"]
  }
}

resource "aws_iam_user_policy" "svc_numeriseur" {
  name   = "numeriseur-scans-bucket"
  user   = aws_iam_user.svc_numeriseur.name
  policy = data.aws_iam_policy_document.svc_numeriseur.json
}

# ---------------------------------------------------------------------------
# homelab backup writers — docker and pi-02
# ---------------------------------------------------------------------------
#
# These two use customer-managed policies rather than inline ones, so they are
# aws_iam_policy + aws_iam_user_policy_attachment.
#
# The docker policy is prefix-scoped per service. THE ORDER OF THIS LIST MATTERS
# only in that changing it produces noisy (but harmless) plan diffs — it mirrors
# the live document. Adding a service to the backup set means adding its prefix
# here, otherwise the upload fails with AccessDenied at 01:05 and the first you
# hear of it is a missing backup.

locals {
  homelab_backup_docker_prefixes = [
    "netbox-postgres",
    "netalertx",
    "netbox-media",
    "unifi-mongo",
    "router",
    "kuma",
    "ntfy",
    "cronicle",
    "grafana",
    "n8n",
    "numeriseur-sftpgo",
  ]
}

data "aws_iam_policy_document" "homelab_backup_docker_write" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = concat(
      [aws_s3_bucket.homelab_backups.arn],
      [for p in local.homelab_backup_docker_prefixes : "${aws_s3_bucket.homelab_backups.arn}/${p}/*"],
    )
  }
}

resource "aws_iam_policy" "homelab_backup_docker_write" {
  name   = "homelab-backup-docker-write"
  policy = data.aws_iam_policy_document.homelab_backup_docker_write.json
}

resource "aws_iam_user" "docker_homelab_backup" {
  name = "docker-homelab-backup"
}

resource "aws_iam_user_policy_attachment" "docker_homelab_backup" {
  user       = aws_iam_user.docker_homelab_backup.name
  policy_arn = aws_iam_policy.homelab_backup_docker_write.arn
}

data "aws_iam_policy_document" "homelab_backup_pi-02_write" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.homelab_backups.arn,
      "${aws_s3_bucket.homelab_backups.arn}/pi-02/*",
    ]
  }
}

resource "aws_iam_policy" "homelab_backup_pi-02_write" {
  name   = "homelab-backup-pi-02-write"
  policy = data.aws_iam_policy_document.homelab_backup_pi-02_write.json
}

resource "aws_iam_user" "pi-02_homelab_backup" {
  name = "pi-02-homelab-backup"
}

resource "aws_iam_user_policy_attachment" "pi-02_homelab_backup" {
  user       = aws_iam_user.pi-02_homelab_backup.name
  policy_arn = aws_iam_policy.homelab_backup_pi-02_write.arn
}
