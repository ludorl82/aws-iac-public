# Import blocks for phase 5: Route53 shrt.example + CloudFront + the ACM cert.
#
# Records import as "ZONEID_name_TYPE". NS and SOA are imported too so the
# zone is fully described — otherwise they read as drift forever.

import {
  to = aws_route53_zone.shrt_example
  id = "Z3763GCGZU6IDP"
}

import {
  to = aws_route53_record.shrt_example_apex_a
  id = "Z3763GCGZU6IDP_shrt.example_A"
}

import {
  to = aws_route53_record.shrt_example_ns
  id = "Z3763GCGZU6IDP_shrt.example_NS"
}

import {
  to = aws_route53_record.shrt_example_soa
  id = "Z3763GCGZU6IDP_shrt.example_SOA"
}

import {
  to = aws_route53_record.shrt_example_acm_validation
  id = "Z3763GCGZU6IDP__4b5f4e60841efcfb586927d1a2c58c2e.shrt.example_CNAME"
}

import {
  to = aws_cloudfront_distribution.shrt_example
  id = "EWDRKSTHXOKI7"
}

# CloudFront-attached ACM certs are us-east-1 only; the provider alias exists
# solely for this.
import {
  provider = aws.us_east_1
  to       = aws_acm_certificate.shrt_example
  id       = "arn:aws:acm:us-east-1:123456789012:certificate/7c1c94ef-3758-4325-a524-5ed177426b5a"
}
