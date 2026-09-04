# Frontend delivery and material storage for the AIAE Onboarding Platform.
#
# One CloudFront distribution presents a single browser origin:
#   /            -> private S3 bucket holding the built SPA
#   /api/*       -> the application's ALB
#   /actuator/*  -> the application's ALB
# Because the browser sees one origin, the SPA keeps runtimeConfig.apiBaseUrl
# empty and needs no build-time API URL. In DEV the generated
# *.cloudfront.net domain is used directly, which also supplies TLS without any
# ACM certificate or GoDaddy record.

# ---------------------------------------------------------------------------
# SPA bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket        = local.onboarding_frontend_bucket_name
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_ownership_controls" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_frontend[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket                  = aws_s3_bucket.onboarding_frontend[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_frontend[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_frontend[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Materials bucket (user uploads)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "onboarding_materials" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket        = local.onboarding_materials_bucket_name
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_public_access_block" "onboarding_materials" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket                  = aws_s3_bucket.onboarding_materials[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "onboarding_materials" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_materials[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The browser PUTs a file straight to a presigned S3 URL, so S3 itself — not
# CloudFront — answers that cross-origin request and needs its own CORS rule.
# Without it the upload fails in the browser with an opaque CORS error while
# the backend reports success at handing out the URL.
resource "aws_s3_bucket_cors_configuration" "onboarding_materials" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_materials[0].id

  cors_rule {
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = compact([
      "https://${aws_cloudfront_distribution.onboarding_frontend[0].domain_name}",
      var.onboarding_frontend_domain_name == "" ? "" : "https://${var.onboarding_frontend_domain_name}",
    ])
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ---------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------

# Declared separately rather than reusing the Operational Hub data sources:
# those are gated on var.enable_frontend and var.frontend_api_origin_domain_name,
# so borrowing them would make this application's plan fail whenever Operational
# Hub's frontend flags change. These are AWS-managed global policies; looking
# them up twice is free.
data "aws_cloudfront_cache_policy" "onboarding_caching_optimized" {
  count = var.enable_onboarding_platform ? 1 : 0

  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "onboarding_caching_disabled" {
  count = var.enable_onboarding_platform ? 1 : 0

  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "onboarding_all_viewer_except_host" {
  count = var.enable_onboarding_platform ? 1 : 0

  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_origin_access_control" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  name                              = "${local.onboarding_name}-frontend"
  description                       = "Private S3 access for the AIAE Onboarding Platform frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Rewrites extension-less paths to /index.html so a deep link such as
# /roadmaps/42 opened directly still loads the SPA instead of returning the S3
# NoSuchKey error.
resource "aws_cloudfront_function" "onboarding_frontend_spa" {
  count = var.enable_onboarding_platform ? 1 : 0

  name    = "${local.onboarding_name}-spa-routing"
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

resource "aws_cloudfront_response_headers_policy" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  name = "${local.onboarding_name}-security-headers"

  security_headers_config {
    content_type_options {
      override = true
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

  # No frame_options here: the application sets its own Content-Security-Policy
  # frame-ancestors (app.security.csp.frame-ancestors), and a CloudFront
  # X-Frame-Options: DENY would override that and break the embedded YouTube
  # and Clerk flows the product relies on.
}

resource "aws_cloudfront_distribution" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.onboarding_name} frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  # Every name the certificate covers is accepted here. Attaching an alias does
  # not route anything to this distribution; DNS decides that.
  aliases = var.onboarding_frontend_domain_name == "" ? [] : concat(
    [var.onboarding_frontend_domain_name],
    var.onboarding_frontend_certificate_alternative_names,
  )

  origin {
    domain_name              = aws_s3_bucket.onboarding_frontend[0].bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.onboarding_frontend[0].id
  }

  dynamic "origin" {
    for_each = var.onboarding_frontend_api_origin_domain_name == "" ? [] : [var.onboarding_frontend_api_origin_domain_name]

    content {
      domain_name = origin.value
      origin_id   = "backend-alb"

      # http-only: the DEV ALB listens on HTTP 80 with no ACM certificate.
      # TLS terminates at CloudFront. PROD should move this to https-only once
      # the ALB carries a certificate.
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
    cache_policy_id            = data.aws_cloudfront_cache_policy.onboarding_caching_optimized[0].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.onboarding_frontend[0].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.onboarding_frontend_spa[0].arn
    }
  }

  # API traffic must not be cached, and must forward the Authorization header
  # that Clerk bearer tokens travel in — hence CachingDisabled plus
  # AllViewerExceptHostHeader.
  dynamic "ordered_cache_behavior" {
    for_each = var.onboarding_frontend_api_origin_domain_name == "" ? [] : ["/api/*", "/actuator/*"]

    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = "backend-alb"
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods             = ["GET", "HEAD", "OPTIONS"]
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.onboarding_caching_disabled[0].id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.onboarding_all_viewer_except_host[0].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.onboarding_frontend[0].id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.onboarding_frontend_domain_name == "" ? true : null
    acm_certificate_arn            = var.onboarding_frontend_domain_name == "" ? null : aws_acm_certificate.onboarding_frontend[0].arn
    ssl_support_method             = var.onboarding_frontend_domain_name == "" ? null : "sni-only"
    minimum_protocol_version       = var.onboarding_frontend_domain_name == "" ? "TLSv1" : "TLSv1.2_2021"
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.onboarding_frontend,
    aws_s3_bucket_public_access_block.onboarding_frontend,
    aws_s3_bucket_server_side_encryption_configuration.onboarding_frontend,
  ]
}

# Only created when a custom hostname is requested. DEV leaves
# onboarding_frontend_domain_name empty and uses the generated CloudFront
# domain, so no certificate and no external DNS work is required.
resource "aws_acm_certificate" "onboarding_frontend" {
  count = var.enable_onboarding_platform && local.onboarding_frontend_certificate_domain_name != "" ? 1 : 0

  domain_name               = local.onboarding_frontend_certificate_domain_name
  subject_alternative_names = var.onboarding_frontend_certificate_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "onboarding_frontend_bucket" {
  count = var.enable_onboarding_platform ? 1 : 0

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.onboarding_frontend[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.onboarding_frontend[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "onboarding_frontend" {
  count = var.enable_onboarding_platform ? 1 : 0

  bucket = aws_s3_bucket.onboarding_frontend[0].id
  policy = data.aws_iam_policy_document.onboarding_frontend_bucket[0].json
}
