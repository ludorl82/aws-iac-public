# External dead-man's switch (backlog item, built 2026-08-03).
#
# Kuma + ntfy live inside k3s: a cluster, aws-node, house-power or WAN
# failure silences the very thing that would report it. Two S3 heartbeats
# (house = pi-02 systemd timer, cluster = k3s CronJob in the kuma
# namespace) are checked by this out-of-VPC Lambda on a 15-minute
# schedule; staleness
# alerts go through SNS email — a delivery path that shares nothing with
# the homelab. One email on stale, one on recovery (state markers under
# deadman/.alerted/ dedupe).
#
# Heartbeats every 5 min, threshold 30 min, check every 15 min:
# worst-case detection ~45 min after the lights go out.

locals {
  deadman_checks = {
    "deadman/house.heartbeat"   = 1800
    "deadman/cluster.heartbeat" = 1800
  }
}

# --- alert delivery --------------------------------------------------------

resource "aws_sns_topic" "deadman" {
  name = "deadman-switch"
}

resource "aws_sns_topic_subscription" "deadman_email" {
  topic_arn = aws_sns_topic.deadman.arn
  protocol  = "email"
  endpoint  = "alerts@example.com"
}

# --- function --------------------------------------------------------------

data "archive_file" "deadman" {
  type        = "zip"
  source_file = "${path.module}/deadman/lambda_function.py"
  output_path = "${path.module}/deadman/.build/deadman.zip"
}

resource "aws_iam_role" "deadman_lambda" {
  name = "deadman-switch-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "deadman_logs" {
  role       = aws_iam_role.deadman_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Cutover complete 2026-08-05: the old homelab-backups grants are gone, so
# this role can no longer touch the backups bucket at all. The function reads
# and writes only its own bucket now — heartbeats plus the .alerted/ markers
# that dedupe alerts.
data "aws_iam_policy_document" "deadman_lambda" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.deadman.arn}/deadman/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.deadman.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.deadman.arn]
  }
}

resource "aws_iam_role_policy" "deadman_lambda" {
  name   = "deadman-switch"
  role   = aws_iam_role.deadman_lambda.id
  policy = data.aws_iam_policy_document.deadman_lambda.json
}

resource "aws_lambda_function" "deadman" {
  function_name    = "deadman-switch"
  role             = aws_iam_role.deadman_lambda.arn
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 30
  filename         = data.archive_file.deadman.output_path
  source_code_hash = data.archive_file.deadman.output_base64sha256

  environment {
    variables = {
      BUCKET    = aws_s3_bucket.deadman.bucket
      TOPIC_ARN = aws_sns_topic.deadman.arn
      CHECKS    = jsonencode(local.deadman_checks)
    }
  }

  tags = {
    Project = "deadman-switch"
  }
}

# --- schedule --------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "deadman" {
  name                = "deadman-switch-check"
  schedule_expression = "rate(15 minutes)"
}

resource "aws_cloudwatch_event_target" "deadman" {
  rule = aws_cloudwatch_event_rule.deadman.name
  arn  = aws_lambda_function.deadman.arn
}

resource "aws_lambda_permission" "deadman_events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deadman.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deadman.arn
}
