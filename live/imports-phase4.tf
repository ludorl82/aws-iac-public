# Import blocks for phase 4: roles, instance profiles, customer-managed
# policies, the admin user and the admin group.
#
# Import id formats used here:
#   aws_iam_role                   RoleName
#   aws_iam_instance_profile       ProfileName
#   aws_iam_policy                 full ARN
#   aws_iam_role_policy            RoleName:InlinePolicyName
#   aws_iam_role_policy_attachment RoleName/PolicyArn
#   aws_iam_user_policy_attachment UserName/PolicyArn
#   aws_iam_group                  GroupName
#   aws_iam_group_policy_attachment GroupName/PolicyArn

# --- live roles ------------------------------------------------------------

import {
  to = aws_iam_role.aws_node
  id = "RoleAws"
}

import {
  to = aws_iam_instance_profile.aws_node
  id = "RoleAws"
}

import {
  to = aws_iam_role.cloudfront_ips
  id = "RoleCloudFrontIps"
}

import {
  to = aws_iam_role.short_url_lambda
  id = "short_url_lambda_iam"
}

# --- customer-managed policies ---------------------------------------------

import {
  to = aws_iam_policy.tpp_aws_s3_full
  id = "arn:aws:iam::123456789012:policy/tpp-aws-s3-full"
}

import {
  to = aws_iam_policy.tpp_numeriseur_keepass_backups
  id = "arn:aws:iam::123456789012:policy/tpp-numeriseur-keepass-backups"
}

import {
  to = aws_iam_policy.tpp_cloudfront_ips
  id = "arn:aws:iam::123456789012:policy/tpp-cloudfront-ips"
}

import {
  to = aws_iam_policy.short_url_s3
  id = "arn:aws:iam::123456789012:policy/short_url_s3_policy"
}

import {
  to = aws_iam_policy.short_url_ssm
  id = "arn:aws:iam::123456789012:policy/short_url_ssm_policy"
}

# --- role policy attachments -----------------------------------------------

import {
  to = aws_iam_role_policy_attachment.aws_node_s3_full
  id = "RoleAws/arn:aws:iam::123456789012:policy/tpp-aws-s3-full"
}

import {
  to = aws_iam_role_policy_attachment.aws_node_keepass
  id = "RoleAws/arn:aws:iam::123456789012:policy/tpp-numeriseur-keepass-backups"
}

import {
  to = aws_iam_role_policy_attachment.cloudfront_ips
  id = "RoleCloudFrontIps/arn:aws:iam::123456789012:policy/tpp-cloudfront-ips"
}

import {
  to = aws_iam_role_policy_attachment.short_url_s3
  id = "short_url_lambda_iam/arn:aws:iam::123456789012:policy/short_url_s3_policy"
}

import {
  to = aws_iam_role_policy_attachment.short_url_ssm
  id = "short_url_lambda_iam/arn:aws:iam::123456789012:policy/short_url_ssm_policy"
}

# --- the admin user --------------------------------------------------------

import {
  to = aws_iam_user.ludorl82
  id = "ludorl82"
}

import {
  to = aws_iam_user_policy_attachment.ludorl82_admin
  id = "ludorl82/arn:aws:iam::aws:policy/AdministratorAccess"
}

