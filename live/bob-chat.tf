# The account-wide budget alarm, which is all that is left of gpu-01-chat here.
#
# The Bedrock half is gone: gpu-01 has run on qwen3:14b on the lab's own GPU since
# 2026-09-07, so the `gpu-01-chat` IAM user, its invoke-Haiku-only policy and its
# access key were removed. Git holds the shape if Bedrock is ever wanted back.
#
# This file keeps its name because the budget below was written here, and the
# budget is NOT about Bedrock — see its own comment.

# --- spend alerting ---------------------------------------------------------
#
# Honest about what this is and is not: an ALERT, not a hard stop. AWS Budgets
# evaluate on AWS's own schedule — hours, not seconds.
#
# It outlived the thing it was written next to, on purpose. This watches the
# WHOLE account — EC2, S3, Route 53, the lot, ~$44/month baseline — so removing
# it with the Bedrock plumbing would have taken the net out from under
# everything else to tidy away one retired feature.
#
# Account-wide rather than filtered to a service on purpose. Claude on Bedrock is
# billed through AWS Marketplace and the model card says charges appear under
# the model provider rather than under "Amazon Bedrock", so a Service cost
# filter could silently match nothing — the worst possible failure for a budget.
# Baseline spend is ~$44/month (Jul $43.51, Aug $44.71), so $60 leaves headroom
# for normal variation while still catching a runaway well before it hurts.
resource "aws_budgets_budget" "account_monthly" {
  name         = "account-monthly"
  budget_type  = "COST"
  limit_amount = "60"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.deadman.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.deadman.arn]
  }
}
