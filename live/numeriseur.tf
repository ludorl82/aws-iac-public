# numeriseur post-upload processing — the Lambda that replaced the SFTPGo hook.
#
# SFTPGo (in k3s) writes scans straight to S3 with no local storage; this
# function does what post-upload.sh used to do inside that container. Moving it
# here is what lets the workload run the stock drakkan/sftpgo image: imagemagick,
# rclone, awscli and openssh-client were all in the custom image for the hook.
#
# UNLIKE the three functions in lambdas.tf, this one's CODE IS MANAGED HERE.
# Those are legacy imports whose code predates the repo; this is new, and it
# follows the deadman pattern — source in live/numeriseur/, archive_file, plan
# shows a code change as a diff. The one difference from deadman is that the
# package has a binary dependency (Pillow), so it cannot be zipped straight from
# the source file: live/numeriseur/build.sh fetches the aarch64 wheel first and
# BOTH GitHub Actions workflows run it before tofu. Running `tofu plan` without
# having run build.sh fails on a missing directory.

locals {
  numeriseur_lambda_pkg = "${path.module}/numeriseur/.build/pkg"
}

# --- packaging -------------------------------------------------------------

data "archive_file" "numeriseur" {
  type        = "zip"
  source_dir  = local.numeriseur_lambda_pkg
  output_path = "${path.module}/numeriseur/.build/numeriseur.zip"
}

# --- credentials -----------------------------------------------------------
#
# The secret's VALUE is deliberately not managed here — it holds Google OAuth
# client credentials and refresh tokens, and this repo's whole doctrine is that
# secrets are piped in out of band rather than living in git. tofu owns the
# container and the access policy; `aws secretsmanager put-secret-value` owns
# what is inside it. See README for the document shape.

resource "aws_secretsmanager_secret" "numeriseur_google_drive" {
  name        = "numeriseur/google-drive"
  description = "Dedicated OAuth client + per-account refresh tokens for the scanner pipeline"
}

# --- alerting --------------------------------------------------------------
#
# Delivered over the DEADMAN topic (live/deadman.tf), not a topic of its own.
# The reasoning for SNS email is unchanged — a delivery path that shares
# nothing with the homelab, so a scan that never reached Drive is still
# reportable when k3s is the broken thing — but there is no reason for a
# second copy of it.
#
# There used to be a `numeriseur-processor` topic here with its own email
# subscription, and it never worked. An SNS email subscription is created in
# `PendingConfirmation` and AWS drops it after 3 days unless someone clicks
# the link; OpenTofu cannot click it. CloudTrail shows `Subscribe` called on
# 2026-08-05, 08-07 and 08-10 — created, expired, recreated — and not one of
# those confirmation mails ever arrived, while ordinary notifications to the
# same address over the deadman topic arrive fine. So the alarm had been
# publishing into a topic with zero subscribers: a failed scan would have
# alarmed into nothing, which is the exact failure this alerting exists to
# catch.
#
# Reusing the confirmed subscription removes a resource that could not be
# confirmed, and with it a recurring nightly drift with a 3-day fuse. If a
# separate stream is ever wanted, the blocker is delivering ONE confirmation
# mail — not the Terraform.
# Lambda retries an async invocation twice and then drops it. The DLQ is what
# turns "a scan silently never arrived" — the old hook's failure mode, a line in
# a hook.log inside a container nobody reads — into something with an alarm on
# it. Messages here are replayable by hand via the function's backfill mode.
resource "aws_sqs_queue" "numeriseur_dlq" {
  name                      = "numeriseur-processor-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
}

resource "aws_cloudwatch_metric_alarm" "numeriseur_dlq" {
  alarm_name          = "numeriseur-processor-dlq-not-empty"
  alarm_description   = "A scan failed processing and was parked on the DLQ. Replay with the function's backfill mode once fixed."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.numeriseur_dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deadman.arn]
  ok_actions          = [aws_sns_topic.deadman.arn]
}

# --- IAM -------------------------------------------------------------------

resource "aws_iam_role" "numeriseur_lambda" {
  name = "numeriseur-processor-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "numeriseur_logs" {
  role       = aws_iam_role.numeriseur_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "numeriseur_lambda" {
  # Read-only on the scans bucket. Note what is NOT here: PutObject. The old
  # hook wrote processed JPEGs back into the same prefix that triggered it,
  # which under S3 events is an infinite loop. Derivatives now exist only in
  # memory and in Drive, and the missing permission enforces that.
  statement {
    sid       = "ReadScans"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.numeriseur_scans.arn}/*"]
  }

  # ListBucket is for the backfill mode only.
  statement {
    sid       = "ListScans"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.numeriseur_scans.arn]
  }

  statement {
    sid       = "ReadGoogleCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.numeriseur_google_drive.arn]
  }

  statement {
    sid       = "ParkFailures"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.numeriseur_dlq.arn]
  }
}

resource "aws_iam_role_policy" "numeriseur_lambda" {
  name   = "numeriseur-processor"
  role   = aws_iam_role.numeriseur_lambda.id
  policy = data.aws_iam_policy_document.numeriseur_lambda.json
}

# --- function --------------------------------------------------------------

resource "aws_cloudwatch_log_group" "numeriseur" {
  name              = "/aws/lambda/numeriseur-processor"
  retention_in_days = 30
}

resource "aws_lambda_function" "numeriseur" {
  function_name = "numeriseur-processor"
  role          = aws_iam_role.numeriseur_lambda.arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  architectures = ["arm64"] # build.sh fetches manylinux2014_aarch64 wheels to match

  # Pillow on a full-bed 300dpi scan, plus the upload. Generous on both: the
  # function runs a handful of times a day and the cost of an oversized timeout
  # is zero, while the cost of a truncated one is a scan that never arrives.
  memory_size = 512
  timeout     = 120

  filename         = data.archive_file.numeriseur.output_path
  source_code_hash = data.archive_file.numeriseur.output_base64sha256

  # NOT attached to the VPC, deliberately: S3 and Google are both public
  # endpoints, so a VPC-attached function would need a NAT gateway to reach
  # either — a standing monthly charge to make the network strictly worse.
  environment {
    variables = {
      BUCKET    = aws_s3_bucket.numeriseur_scans.bucket
      SECRET_ID = aws_secretsmanager_secret.numeriseur_google_drive.name
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.numeriseur_dlq.arn
  }

  tags = {
    Project = "numeriseur"
  }

  depends_on = [aws_cloudwatch_log_group.numeriseur]
}

# --- trigger ---------------------------------------------------------------
#
# EventBridge rather than S3 bucket notifications. Native notifications filter
# on prefix/suffix only and reject overlapping prefix rules, which gets awkward
# with five user prefixes; EventBridge does real pattern matching and is far
# nicer to express here. The rule matches every object created in the bucket and
# lets the function route on the key — the bucket holds nothing but scans, and a
# key that does not match <user>/<vdir>/<file> gets a log line rather than a
# guess.

resource "aws_s3_bucket_notification" "numeriseur_scans" {
  bucket      = aws_s3_bucket.numeriseur_scans.id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "numeriseur_upload" {
  name        = "numeriseur-scan-uploaded"
  description = "SFTPGo wrote a scan to the numeriseur bucket"

  # ENABLED 2026-08-05, once the k3s side went stock and the action hook stopped
  # running. It shipped DISABLED so that the hook and this rule could never both
  # be live — they push to the same Drive folders, so an overlap double-delivers
  # every scan, and duplicates in Drive need manual cleanup while a gap does not
  # (S3 keeps the object; the function's backfill mode replays it).
  state = "ENABLED"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.numeriseur_scans.bucket] }
    }
  })
}

resource "aws_cloudwatch_event_target" "numeriseur_upload" {
  rule = aws_cloudwatch_event_rule.numeriseur_upload.name
  arn  = aws_lambda_function.numeriseur.arn
}

resource "aws_lambda_permission" "numeriseur_events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.numeriseur.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.numeriseur_upload.arn
}
