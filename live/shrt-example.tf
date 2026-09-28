# Phase 5: the shrt.example short-URL stack — Route53 zone, CloudFront distribution,
# and its ACM certificate (us-east-1, as CloudFront requires).
#
# Drafted with `tofu plan -generate-config-out` and folded by hand: the raw
# generated config is unusable as-is (empty-string values for attributes that
# must be omitted — origin_access_control_id, certificate_authority_arn — and
# ttl/records on an alias record). What remains matches live exactly.
#
# The lambdas that write into the bucket behind this are phase 6.

resource "aws_route53_zone" "shrt_example" {
  name = "shrt.example"

  # Live comment is genuinely empty. Omitting this would drift to the
  # provider's "Managed by Terraform" default.
  comment = ""

  lifecycle {
    prevent_destroy = true
  }
}

# NS and SOA are Amazon-assigned but imported so the zone is fully described.
resource "aws_route53_record" "shrt_example_ns" {
  zone_id = aws_route53_zone.shrt_example.zone_id
  name    = "shrt.example"
  type    = "NS"
  ttl     = 172800

  records = [
    "ns-1509.awsdns-60.org.",
    "ns-1671.awsdns-16.co.uk.",
    "ns-413.awsdns-51.com.",
    "ns-812.awsdns-37.net.",
  ]
}

resource "aws_route53_record" "shrt_example_soa" {
  zone_id = aws_route53_zone.shrt_example.zone_id
  name    = "shrt.example"
  type    = "SOA"
  ttl     = 900

  records = ["ns-1671.awsdns-16.co.uk. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400"]
}

resource "aws_route53_record" "shrt_example_apex_a" {
  zone_id = aws_route53_zone.shrt_example.zone_id
  name    = "shrt.example"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.shrt_example.domain_name
    zone_id                = aws_cloudfront_distribution.shrt_example.hosted_zone_id
    evaluate_target_health = false
  }
}

# DNS validation for the ACM cert below. Kept as a plain record (not an
# aws_acm_certificate_validation dance) — the cert has been issued for years;
# this record just has to keep existing for renewals.
resource "aws_route53_record" "shrt_example_acm_validation" {
  zone_id = aws_route53_zone.shrt_example.zone_id
  name    = "_4b5f4e60841efcfb586927d1a2c58c2e.shrt.example"
  type    = "CNAME"
  ttl     = 60

  records = ["_2d3fce85d009f9fad212719048d2d2f9.olprtlswtu.acm-validations.aws."]
}

resource "aws_acm_certificate" "shrt_example" {
  provider = aws.us_east_1

  domain_name               = "shrt.example"
  subject_alternative_names = ["shrt.example"]
  key_algorithm             = "RSA_2048"
  validation_method         = "DNS"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  tags = {
    Project = "short_urls"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudfront_distribution" "shrt_example" {
  aliases         = ["shrt.example"]
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = false
  price_class     = "PriceClass_All"

  # The origin is the S3 *website endpoint* (a custom origin, plain HTTP by
  # nature), not the S3 REST endpoint — the website config's index-suffix
  # "web" routing is what makes the short URLs resolve.
  origin {
    origin_id           = "origin-bucket-shrt.example"
    domain_name         = "shrt.example.s3-website.ca-central-1.amazonaws.com"
    connection_attempts = 3
    connection_timeout  = 10

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
      # Dated (TLS 1.1), but irrelevant in practice: origin traffic is
      # http-only. Left as live.
      origin_ssl_protocols = ["TLSv1.1"]
    }
  }

  # Legacy forwarded_values (no cache policies) with all TTLs zero — every
  # request revalidates at origin. That is the live behaviour and plausibly
  # deliberate for instantly-editable short URLs; do not "modernise" casually.
  default_cache_behavior {
    target_origin_id       = "origin-bucket-shrt.example"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.shrt_example.arn
    ssl_support_method  = "sni-only"
    # Dated; raising it is a real (if low-risk) change — do it deliberately,
    # not as an import side effect.
    minimum_protocol_version = "TLSv1.1_2016"
  }

  tags = {
    Project = "short_urls"
  }

  lifecycle {
    prevent_destroy = true
  }
}
