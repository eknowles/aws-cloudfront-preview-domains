locals {
  domain_name     = "example.com"
  cdn_domain_name = "cdn.${local.domain_name}"
  wildcard_domain = "*.${local.cdn_domain_name}"
  bucket_name     = "example-test-webapp"
}

data "aws_route53_zone" "external" {
  name = "${local.domain_name}."
}

# Part 1 - Create the SSL Certificate
resource "aws_acm_certificate" "main" {
  domain_name               = local.cdn_domain_name
  subject_alternative_names = [local.wildcard_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_route53_record" "validation" {
  name    = aws_acm_certificate.main.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.main.domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.main.domain_validation_options[0].resource_record_value]

  zone_id         = data.aws_route53_zone.external.zone_id
  ttl             = 60
  allow_overwrite = true
}
resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
  validation_record_fqdns = [
    aws_route53_record.validation.fqdn
  ]

  timeouts {
    create = "10m"
  }
}

# Part 2 - Create S3 Bucket
resource "aws_s3_bucket" "bucket" {
  bucket = local.bucket_name
  acl    = "public-read"
  policy = data.aws_iam_policy_document.bucket.json

  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}
data "aws_iam_policy_document" "bucket" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${local.bucket_name}",
      "arn:aws:s3:::${local.bucket_name}/*"
    ]
    principals {
      identifiers = ["*"]
      type        = "*"
    }
  }
}

# Part 3 - Lambda@Edge
module "viewer_request_lambda" {
  source        = "./modules/edge-lambda"
  function_name = "viewer-request"
}
module "origin_request_lambda" {
  source        = "./modules/edge-lambda"
  function_name = "origin-request"
}

# Part 4 - Create CloudFront
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [local.cdn_domain_name, local.wildcard_domain]

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.main.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  origin {
    domain_name = aws_s3_bucket.bucket.website_endpoint
    origin_id   = "app"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "app"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    min_ttl                = 0
    default_ttl            = 0 # 3600
    max_ttl                = 0 # 86400
    viewer_protocol_policy = "redirect-to-https"

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = module.origin_request_lambda.qualified_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = module.viewer_request_lambda.qualified_arn
      include_body = false
    }

    forwarded_values {
      query_string = false
      headers      = ["x-forwarded-host"]

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
}

# Part 5 - Add A Record to CDN
resource "aws_route53_record" "wildcard_cdn" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = local.wildcard_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
resource "aws_route53_record" "naked_cdn" {
  zone_id = data.aws_route53_zone.external.zone_id
  name    = local.cdn_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

#Test data
resource "aws_s3_bucket_object" "root_index" {
  key          = "index.html"
  bucket       = aws_s3_bucket.bucket.id
  content      = "i am root"
  content_type = "text/html"
}
resource "aws_s3_bucket_object" "error_index" {
  key          = "error.html"
  bucket       = aws_s3_bucket.bucket.id
  content      = "i am error"
  content_type = "text/html"
}
resource "aws_s3_bucket_object" "master_branch_index" {
  key          = "master/index.html"
  bucket       = aws_s3_bucket.bucket.id
  content      = "i am master"
  content_type = "text/html"
}
resource "aws_s3_bucket_object" "feature_branch_index" {
  key          = "feature/index.html"
  bucket       = aws_s3_bucket.bucket.id
  content      = "i am a feature"
  content_type = "text/html"
}
