# GitHub Actions OIDC — CI deployment identities for the IaC repos.
#
# The repos deploy from GitHub-hosted runners with NO stored AWS keys: a
# workflow exchanges its GitHub-signed OIDC token for short-lived credentials
# via sts:AssumeRoleWithWebIdentity. What limits the blast radius is the trust
# policy's `sub` condition — a role is assumable only from the exact repo and
# context it names:
#
#   repo:<owner>/<repo>:pull_request        — plan jobs (PR context)
#   repo:<owner>/<repo>:ref:refs/heads/...  — apply jobs (push to the branch)
#
# Two roles per repo, deliberately asymmetric: the plan role is read-only
# (plans run with -lock=false and never write), the apply role has what apply
# actually needs. A compromised PR can therefore read but not change anything;
# changing things requires a commit landing on master, which is the gate.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's cert against trusted root CAs since 2023 and
  # ignores these, but the API still requires the field. Both historical
  # thumbprints, per GitHub's own guidance.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

locals {
  tfstate_bucket_arn = "arn:aws:s3:::tfstate-example-com"
}

# Trust policy factory in all but name: identical shape for every role, only
# the `sub` pattern differs.
#
# Each sub is accepted in BOTH GitHub formats: the classic
# `repo:<owner>/<repo>:<context>` and the immutable-subject variant GitHub now
# issues, `repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>` — discovered
# the hard way when every classic-only trust policy failed with "Not
# authorized to perform sts:AssumeRoleWithWebIdentity". The IDs are immutable
# (that is the feature), so listing both loosens nothing: owner 34710674 is
# ludorl82, and the repo ids survive even a repo rename.
data "aws_iam_policy_document" "gha_trust" {
  for_each = {
    cloudflare_iac_plan = [
      "repo:ludorl82/cloudflare-iac:pull_request",
      "repo:ludorl82@34710674/cloudflare-iac@1312256183:pull_request",
    ]
    cloudflare_iac_apply = [
      "repo:ludorl82/cloudflare-iac:ref:refs/heads/master",
      "repo:ludorl82@34710674/cloudflare-iac@1312256183:ref:refs/heads/master",
    ]
    aws_iac_plan = [
      "repo:ludorl82/aws-iac:pull_request",
      "repo:ludorl82@34710674/aws-iac@1312256127:pull_request",
    ]
    aws_iac_apply = [
      "repo:ludorl82/aws-iac:ref:refs/heads/master",
      "repo:ludorl82@34710674/aws-iac@1312256127:ref:refs/heads/master",
    ]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# cloudflare-iac — AWS is only the state backend for this repo. The plan role
# reads the state object; the apply role can also write it (and the .tflock
# conditional-write lockfile next to it). Neither can touch anything else in
# the account, including other state keys in the same bucket.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_cloudflare_iac_plan" {
  name               = "gha-cloudflare-iac-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["cloudflare_iac_plan"].json
}

data "aws_iam_policy_document" "cloudflare_state_read" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.tfstate_bucket_arn]
  }

  statement {
    sid       = "ReadCloudflareState"
    actions   = ["s3:GetObject"]
    resources = ["${local.tfstate_bucket_arn}/cloudflare/terraform.tfstate"]
  }
}

resource "aws_iam_role_policy" "gha_cloudflare_iac_plan" {
  name   = "state-read"
  role   = aws_iam_role.gha_cloudflare_iac_plan.id
  policy = data.aws_iam_policy_document.cloudflare_state_read.json
}

resource "aws_iam_role" "gha_cloudflare_iac_apply" {
  name               = "gha-cloudflare-iac-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["cloudflare_iac_apply"].json
}

data "aws_iam_policy_document" "cloudflare_state_write" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.tfstate_bucket_arn]
  }

  statement {
    sid = "ReadWriteCloudflareState"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject", # lockfile removal on unlock
    ]
    resources = ["${local.tfstate_bucket_arn}/cloudflare/terraform.tfstate*"]
  }
}

resource "aws_iam_role_policy" "gha_cloudflare_iac_apply" {
  name   = "state-readwrite"
  role   = aws_iam_role.gha_cloudflare_iac_apply.id
  policy = data.aws_iam_policy_document.cloudflare_state_write.json
}

# ---------------------------------------------------------------------------
# aws-iac — this very repo. Plan needs to read every managed resource plus the
# state, which is what ReadOnlyAccess is; -lock=false keeps it from needing a
# single write. Apply is AdministratorAccess, eyes open: the repo manages IAM,
# EC2, S3 and Lambda, so a tailored policy would converge on admin anyway. The
# real guards are the trust policy (master branch of one repo only) and the
# workflow's destroy gate.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gha_aws_iac_plan" {
  name               = "gha-aws-iac-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["aws_iac_plan"].json
}

resource "aws_iam_role_policy_attachment" "gha_aws_iac_plan_readonly" {
  role       = aws_iam_role.gha_aws_iac_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role" "gha_aws_iac_apply" {
  name               = "gha-aws-iac-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["aws_iac_apply"].json
}

resource "aws_iam_role_policy_attachment" "gha_aws_iac_apply_admin" {
  role       = aws_iam_role.gha_aws_iac_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
