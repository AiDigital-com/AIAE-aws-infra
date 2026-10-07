# Frontend delivery for the AIAE Presentation Builder.
#
# One CloudFront distribution presents a single browser origin:
#   /            -> private S3 bucket holding the built SPA
#   /api/*       -> the application's ALB
#   /actuator/*  -> the application's ALB
# Because the browser sees one origin, the SPA keeps runtimeConfig.apiBaseUrl
# empty and needs no build-time API URL — which is already how
# frontend/src/shared/config/runtime.ts resolves it. In DEV the generated
# *.cloudfront.net domain is used directly, which also supplies TLS without any
# ACM certificate or GoDaddy record.
#
# There is no uploads bucket: this application writes its artifacts to Google
# Slides and Google Sheets, not to S3.

# ---------------------------------------------------------------------------
# SPA bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket        = local.presentation_builder_frontend_bucket_name
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_ownership_controls" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket = aws_s3_bucket.presentation_builder_frontend[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket                  = aws_s3_bucket.presentation_builder_frontend[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is what makes the PROD rollback workflow able to restore a
# previous frontend release rather than rebuild it.
resource "aws_s3_bucket_versioning" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket = aws_s3_bucket.presentation_builder_frontend[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket = aws_s3_bucket.presentation_builder_frontend[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------

# Declared separately rather than reusing another application's data sources:
# those are gated on that application's own enable flags, so borrowing them
# would make this plan fail whenever an unrelated application's frontend flags
# change. These are AWS-managed global policies; looking them up again is free.
data "aws_cloudfront_cache_policy" "presentation_builder_caching_optimized" {
  count = var.enable_presentation_builder ? 1 : 0

  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "presentation_builder_caching_disabled" {
  count = var.enable_presentation_builder ? 1 : 0

  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "presentation_builder_all_viewer_except_host" {
  count = var.enable_presentation_builder ? 1 : 0

  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_origin_access_control" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  name                              = "${local.presentation_builder_name}-frontend"
  description                       = "Private S3 access for the AIAE Presentation Builder frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Rewrites extension-less paths to /index.html so a deep link such as
# /reports/42 or /admin opened directly still loads the SPA instead of
# returning the S3 NoSuchKey error. On Replit this was Spring's job, because
# the SPA was packaged inside the jar; on S3 nothing serves a fallback.
resource "aws_cloudfront_function" "presentation_builder_frontend_spa" {
  count = var.enable_presentation_builder ? 1 : 0

  name    = "${local.presentation_builder_name}-spa-routing"
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

resource "aws_cloudfront_response_headers_policy" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  name = "${local.presentation_builder_name}-security-headers"

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
  # X-Frame-Options: DENY would override it and break the Clerk sign-in flow.
}

resource "aws_cloudfront_distribution" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.presentation_builder_name} frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Exactly the names chosen for attachment — not everything the certificate
  # covers. Attaching an alias does not route anything here; DNS decides that.
  # Empty in DEV, so the generated CloudFront domain is the product URL.
  aliases = var.presentation_builder_frontend_attached_aliases

  origin {
    domain_name              = aws_s3_bucket.presentation_builder_frontend[0].bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.presentation_builder_frontend[0].id
  }

  dynamic "origin" {
    for_each = var.presentation_builder_frontend_api_origin_domain_name == "" ? [] : [var.presentation_builder_frontend_api_origin_domain_name]

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

      # No origin_read_timeout override: report generation is dispatched to an
      # @Async virtual-thread executor and the request returns a job id
      # immediately, so no HTTP response waits on Anthropic or the Google APIs.
      # CloudFront's 30-second default is enough for the polling endpoints.
    }
  }

  default_cache_behavior {
    target_origin_id           = "frontend-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.presentation_builder_caching_optimized[0].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.presentation_builder_frontend[0].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.presentation_builder_frontend_spa[0].arn
    }
  }

  # API traffic must not be cached, and must forward the Authorization header
  # that Clerk bearer tokens travel in — hence CachingDisabled plus
  # AllViewerExceptHostHeader.
  dynamic "ordered_cache_behavior" {
    for_each = var.presentation_builder_frontend_api_origin_domain_name == "" ? [] : ["/api/*", "/actuator/*"]

    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = "backend-alb"
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods             = ["GET", "HEAD", "OPTIONS"]
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.presentation_builder_caching_disabled[0].id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.presentation_builder_all_viewer_except_host[0].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.presentation_builder_frontend[0].id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = length(var.presentation_builder_frontend_attached_aliases) == 0 ? true : null
    acm_certificate_arn            = length(var.presentation_builder_frontend_attached_aliases) == 0 ? null : aws_acm_certificate.presentation_builder_frontend[0].arn
    ssl_support_method             = length(var.presentation_builder_frontend_attached_aliases) == 0 ? null : "sni-only"
    minimum_protocol_version       = length(var.presentation_builder_frontend_attached_aliases) == 0 ? "TLSv1" : "TLSv1.2_2021"
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.presentation_builder_frontend,
    aws_s3_bucket_public_access_block.presentation_builder_frontend,
    aws_s3_bucket_server_side_encryption_configuration.presentation_builder_frontend,
  ]
}

# Only created when a custom hostname is requested. DEV leaves
# presentation_builder_frontend_certificate_request_domain_name empty and uses
# the generated CloudFront domain, so no certificate and no external DNS work is
# required. The production hostname aiae-presentation-builder.aidigital.tech
# still resolves to the Replit deployment and must keep doing so until cutover.
resource "aws_acm_certificate" "presentation_builder_frontend" {
  count = var.enable_presentation_builder && var.presentation_builder_frontend_certificate_request_domain_name != "" ? 1 : 0

  domain_name               = var.presentation_builder_frontend_certificate_request_domain_name
  subject_alternative_names = var.presentation_builder_frontend_certificate_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "presentation_builder_frontend_bucket" {
  count = var.enable_presentation_builder ? 1 : 0

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.presentation_builder_frontend[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.presentation_builder_frontend[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "presentation_builder_frontend" {
  count = var.enable_presentation_builder ? 1 : 0

  bucket = aws_s3_bucket.presentation_builder_frontend[0].id
  policy = data.aws_iam_policy_document.presentation_builder_frontend_bucket[0].json
}
