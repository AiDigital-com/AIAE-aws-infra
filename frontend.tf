resource "aws_s3_bucket" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket        = local.frontend_bucket_name
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket                  = aws_s3_bucket.frontend[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  count = var.enable_frontend ? 1 : 0

  name                              = "${local.name}-frontend"
  description                       = "Private S3 access for the Operational Hub frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  count = var.enable_frontend ? 1 : 0

  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  count = var.enable_frontend && var.frontend_api_origin_domain_name != "" ? 1 : 0

  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  count = var.enable_frontend && var.frontend_api_origin_domain_name != "" ? 1 : 0

  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_function" "frontend_spa" {
  count = var.enable_frontend ? 1 : 0

  name    = "${local.name}-spa-routing"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      if (!uri.includes('.') && !uri.endsWith('/')) {
        request.uri = '/index.html';
      } else if (uri.endsWith('/')) {
        request.uri += 'index.html';
      }
      return request;
    }
  EOT
}

resource "aws_cloudfront_response_headers_policy" "frontend" {
  count = var.enable_frontend ? 1 : 0

  name = "${local.name}-security-headers"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }

    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
  }
}

resource "aws_acm_certificate" "frontend" {
  count = var.enable_frontend && var.frontend_domain_name != "" ? 1 : 0

  domain_name       = var.frontend_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.route53_zone_name != ""
      error_message = "route53_zone_name must be set when frontend_domain_name is configured."
    }
  }
}

resource "aws_route53_record" "frontend_certificate_validation" {
  count = var.enable_frontend && var.frontend_domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_type
  ttl     = 60
  records = [tolist(aws_acm_certificate.frontend[0].domain_validation_options)[0].resource_record_value]
}

resource "aws_acm_certificate_validation" "frontend" {
  count = var.enable_frontend && var.frontend_domain_name != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.frontend[0].arn
  validation_record_fqdns = [aws_route53_record.frontend_certificate_validation[0].fqdn]
}

resource "aws_cloudfront_distribution" "frontend" {
  count = var.enable_frontend ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name} frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.frontend_domain_name == "" ? [] : [var.frontend_domain_name]

  origin {
    domain_name              = aws_s3_bucket.frontend[0].bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend[0].id
  }

  dynamic "origin" {
    for_each = var.frontend_api_origin_domain_name == "" ? [] : [var.frontend_api_origin_domain_name]

    content {
      domain_name = origin.value
      origin_id   = "backend-alb"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = "frontend-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized[0].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend[0].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.frontend_spa[0].arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.frontend_api_origin_domain_name == "" ? [] : ["/api/*", "/actuator/*"]

    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = "backend-alb"
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods             = ["GET", "HEAD", "OPTIONS"]
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled[0].id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host[0].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend[0].id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.frontend_domain_name == "" ? true : null
    acm_certificate_arn            = var.frontend_domain_name == "" ? null : aws_acm_certificate_validation.frontend[0].certificate_arn
    ssl_support_method             = var.frontend_domain_name == "" ? null : "sni-only"
    minimum_protocol_version       = var.frontend_domain_name == "" ? "TLSv1" : "TLSv1.2_2021"
  }

  lifecycle {
    precondition {
      condition     = var.frontend_domain_name == "" || var.frontend_domain_name != var.domain_name
      error_message = "frontend_domain_name must differ from domain_name; the API hostname is owned by the EKS ALB."
    }
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.frontend,
    aws_s3_bucket_public_access_block.frontend,
    aws_s3_bucket_server_side_encryption_configuration.frontend,
  ]
}

data "aws_iam_policy_document" "frontend_bucket" {
  count = var.enable_frontend ? 1 : 0

  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.frontend[0].arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  count = var.enable_frontend ? 1 : 0

  bucket = aws_s3_bucket.frontend[0].id
  policy = data.aws_iam_policy_document.frontend_bucket[0].json
}

resource "aws_route53_record" "frontend_a" {
  count = var.enable_frontend && var.frontend_domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = var.frontend_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend[0].domain_name
    zone_id                = aws_cloudfront_distribution.frontend[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_aaaa" {
  count = var.enable_frontend && var.frontend_domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = var.frontend_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend[0].domain_name
    zone_id                = aws_cloudfront_distribution.frontend[0].hosted_zone_id
    evaluate_target_health = false
  }
}
