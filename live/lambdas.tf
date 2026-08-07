# Phase 6b: the three lambdas and their trigger plumbing.
#
# CODE IS NOT MANAGED HERE. The provider insists on one of
# filename/image_uri/s3_bucket even for imported functions, so each carries a
# placeholder filename that ignore_changes guarantees is never read or
# uploaded — the file deliberately does not exist. Deploying new code stays
# whatever it was before (console/CLI); if that ever becomes a real workflow
# again, wire it properly instead of pointing tofu at a zip.
#
# Estate status, worth knowing before touching anything:
#   - Both short_url rules are DISABLED in live. state = "DISABLED" below is
#     deliberate adoption of that fact — flipping them on is a one-word
#     change, but make it on purpose.
#   - add/del_object_url are driven by SSM Parameter Store change events:
#     creating a parameter creates a short URL. Dormant while the rules are
#     disabled.
#   - AjouterIpsCloudfront is the only live one: Amazon's AmazonIpSpaceChanged
#     SNS topic (us-east-1, Amazon's account) invokes it to sync CloudFront
#     ranges into a security group.
#   - DELETED 2026-07-27: PrendreInstantanes / PurgerInstantanes (python2.7,
#     last ran 2023-11), their BackupQuotidien rule + targets + invoke
#     permissions, and RoleBackup. The EBS snapshots they took were superseded
#     by the homelab-backups pipeline.

# --- functions -------------------------------------------------------------

resource "aws_lambda_function" "add_object_url" {
  # Satisfies the provider's one-of(filename,image_uri,s3_bucket) validation.
  # Never read: ignore_changes below means no code upload is ever planned, so
  # the file does not need to exist. Code stays unmanaged, per the header.
  filename = "unmanaged-see-header-comment.zip"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  function_name = "add_object_url"
  role          = aws_iam_role.short_url_lambda.arn
  runtime       = "python3.7"
  handler       = "lambda_function.lambda_handler"
  architectures = ["x86_64"]
  memory_size   = 128
  timeout       = 3

  environment {
    variables = {
      DOMAIN = "shrt.example"
      PRE    = "shrtexample"
    }
  }

  tags = {
    Project = "short_urls"
  }
}

resource "aws_lambda_function" "del_object_url" {
  # Satisfies the provider's one-of(filename,image_uri,s3_bucket) validation.
  # Never read: ignore_changes below means no code upload is ever planned, so
  # the file does not need to exist. Code stays unmanaged, per the header.
  filename = "unmanaged-see-header-comment.zip"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  function_name = "del_object_url"
  role          = aws_iam_role.short_url_lambda.arn
  runtime       = "python3.7"
  handler       = "lambda_function.lambda_handler"
  architectures = ["x86_64"]
  memory_size   = 128
  timeout       = 3

  environment {
    variables = {
      DOMAIN = "shrt.example"
      PRE    = "shrtexample"
    }
  }

  tags = {
    Project = "short_urls"
  }
}

resource "aws_lambda_function" "ajouter_ips_cloudfront" {
  # Satisfies the provider's one-of(filename,image_uri,s3_bucket) validation.
  # Never read: ignore_changes below means no code upload is ever planned, so
  # the file does not need to exist. Code stays unmanaged, per the header.
  filename = "unmanaged-see-header-comment.zip"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  function_name = "AjouterIpsCloudfront"
  role          = aws_iam_role.cloudfront_ips.arn
  runtime       = "python3.10"
  handler       = "lambda_function.lambda_handler"
  architectures = ["x86_64"]
  memory_size   = 128
  timeout       = 10
}

# --- EventBridge rules + targets -------------------------------------------

resource "aws_cloudwatch_event_rule" "add_object_url" {
  name        = "add_object_url_rule"
  description = "Trigger lambda when changes are made to parameter store"
  state       = "DISABLED"

  event_pattern = jsonencode({
    detail = {
      operation = ["Create", "Update"]
    }
    detail-type = ["Parameter Store Change"]
    source      = ["aws.ssm"]
  })
}

resource "aws_cloudwatch_event_target" "add_object_url" {
  rule      = aws_cloudwatch_event_rule.add_object_url.name
  target_id = "add_object_url"
  arn       = aws_lambda_function.add_object_url.arn
}

resource "aws_cloudwatch_event_rule" "del_object_url" {
  name        = "del_object_url_rule"
  description = "Trigger lambda when params are deleted"
  state       = "DISABLED"

  event_pattern = jsonencode({
    detail = {
      operation = ["Delete"]
    }
    detail-type = ["Parameter Store Change"]
    source      = ["aws.ssm"]
  })
}

resource "aws_cloudwatch_event_target" "del_object_url" {
  rule      = aws_cloudwatch_event_rule.del_object_url.name
  target_id = "del_object_url"
  arn       = aws_lambda_function.del_object_url.arn
}

# --- invoke permissions ----------------------------------------------------

resource "aws_lambda_permission" "add_object_url_events" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_object_url.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.add_object_url.arn
}

resource "aws_lambda_permission" "del_object_url_events" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.del_object_url.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.del_object_url.arn
}

resource "aws_lambda_permission" "ajouter_ips_sns" {
  statement_id  = "lambda-sns-trigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ajouter_ips_cloudfront.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = "arn:aws:sns:us-east-1:210987654321:AmazonIpSpaceChanged"
}

# --- the one live trigger --------------------------------------------------
#
# Amazon's own topic, Amazon's own account (210987654321); the subscription is
# the only piece we own. It must live in the topic's region, hence us-east-1.
resource "aws_sns_topic_subscription" "amazon_ip_space_changed" {
  provider = aws.us_east_1

  topic_arn = "arn:aws:sns:us-east-1:210987654321:AmazonIpSpaceChanged"
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ajouter_ips_cloudfront.arn
}
