# Import blocks for phase 6: the EC2 instance, the lambdas, and their
# trigger plumbing (EventBridge rules/targets, lambda permissions, and the
# cross-account SNS subscription that drives AjouterIpsCloudfront).
#
# The PrendreInstantanes/PurgerInstantanes snapshot pipeline was destroyed on
# 2026-07-27; its import blocks were removed with the resources.
#
# Import id formats:
#   aws_cloudwatch_event_target   "rule-name/target-id"
#   aws_lambda_permission         "function-name/statement-id"
#   aws_sns_topic_subscription    full subscription ARN (topic lives in
#                                 us-east-1 and belongs to Amazon's account)

import {
  to = aws_instance.aws_node
  id = "i-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_lambda_function.add_object_url
  id = "add_object_url"
}

import {
  to = aws_lambda_function.del_object_url
  id = "del_object_url"
}

import {
  to = aws_lambda_function.ajouter_ips_cloudfront
  id = "AjouterIpsCloudfront"
}

import {
  to = aws_cloudwatch_event_rule.add_object_url
  id = "add_object_url_rule"
}

import {
  to = aws_cloudwatch_event_rule.del_object_url
  id = "del_object_url_rule"
}

import {
  to = aws_cloudwatch_event_target.add_object_url
  id = "add_object_url_rule/add_object_url"
}

import {
  to = aws_cloudwatch_event_target.del_object_url
  id = "del_object_url_rule/del_object_url"
}

import {
  to = aws_lambda_permission.add_object_url_events
  id = "add_object_url/AllowExecutionFromCloudWatch"
}

import {
  to = aws_lambda_permission.del_object_url_events
  id = "del_object_url/AllowExecutionFromCloudWatch"
}

import {
  to = aws_lambda_permission.ajouter_ips_sns
  id = "AjouterIpsCloudfront/lambda-sns-trigger"
}

import {
  provider = aws.us_east_1
  to       = aws_sns_topic_subscription.amazon_ip_space_changed
  id       = "arn:aws:sns:us-east-1:210987654321:AmazonIpSpaceChanged:1751e713-bc1e-4d09-aba9-ffcd376f4080"
}
