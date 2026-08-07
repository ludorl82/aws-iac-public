# Phase 3b: the IAM users behind the data pipelines.
#
# ACCESS KEYS ARE NOT MANAGED HERE, deliberately. aws_iam_access_key writes the
# secret into state in plaintext, which would turn the state bucket into a
# credential store. Each of these users has one key, created out of band
# (four between 2026-07-07 and 2026-07-18, cronicle-s3 on 2026-08-07) and
# stored in KeePass; rotating one means creating it by hand and updating the
# consumer.
#
# It was five until 2026-08-07, when `iac-drift` was retired: the nightly drift
# check moved to a GitHub Actions OIDC role (gha-aws-iac-drift, see
# iam-github-oidc.tf) whose credential is minted per run. That is the direction
# for the rest of these — a static key is only still here where the consumer
# cannot federate.
#
# Key IDs are deliberately not listed here — the pre-commit hook treats an
# AKIA… literal as a secret, and they are one command away anyway:
#
#   aws iam list-access-keys --user-name <user>
#
# The human user `ludorl82` (AdministratorAccess) is in iam.tf with the rest of
# phase 4 — it is not a pipeline identity.

# ---------------------------------------------------------------------------
# cronicle-s3 — Cronicle's live storage engine (cronicle namespace on k3s)
# ---------------------------------------------------------------------------
#
# Consumed as AWS_* env vars in the pod (out-of-band k8s Secret
# cronicle-s3-credentials); the SDK default credential chain picks them up, so
# nothing lands in the Cronicle config. DeleteObject is required — Cronicle
# expires history records as part of normal operation. Cannot federate: the
# pod runs on-prem, so this is a static key by necessity.

resource "aws_iam_user" "cronicle_s3" {
  name = "cronicle-s3"
}

data "aws_iam_policy_document" "cronicle_s3" {
  statement {
    sid       = "CronicleBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.cronicle_data.arn]
  }

  statement {
    sid    = "CronicleObjectRW"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.cronicle_data.arn}/*"]
  }
}

resource "aws_iam_user_policy" "cronicle_s3" {
  name   = "cronicle-s3-bucket-only"
  user   = aws_iam_user.cronicle_s3.name
  policy = data.aws_iam_policy_document.cronicle_s3.json
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
    # "deadman" removed 2026-08-05 — the heartbeats now write to their own
    # bucket via deadman-heartbeat-write. Removed only AFTER both writers
    # were confirmed on the new bucket, per the ordering lesson from #5:
    # pulling a prefix while its writer still exists converts a working job
    # into a silent AccessDenied rather than removing it.
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

# Heartbeat writes go to their own bucket (see s3.tf for why they left
# homelab-backups). Deliberately a SEPARATE policy rather than another prefix
# on homelab-backup-docker-write: the two have different lifetimes, and the
# "deadman" entry in local.homelab_backup_docker_prefixes above comes out once
# the writers have moved. Both heartbeat writers — the pi-02 systemd timer
# and the k3s CronJob — authenticate as this same shared user.
data "aws_iam_policy_document" "deadman_heartbeat_write" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.deadman.arn,
      "${aws_s3_bucket.deadman.arn}/deadman/*",
    ]
  }
}

resource "aws_iam_policy" "deadman_heartbeat_write" {
  name   = "deadman-heartbeat-write"
  policy = data.aws_iam_policy_document.deadman_heartbeat_write.json
}

resource "aws_iam_user_policy_attachment" "deadman_heartbeat_write" {
  user       = aws_iam_user.docker_homelab_backup.name
  policy_arn = aws_iam_policy.deadman_heartbeat_write.arn
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
