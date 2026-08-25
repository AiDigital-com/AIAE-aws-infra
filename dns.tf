data "aws_route53_zone" "public" {
  count = local.route53_enabled ? 1 : 0

  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "api" {
  count = var.enable_public_certificate ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.route53_zone_name != ""
      error_message = "route53_zone_name must be set when enable_public_certificate=true."
    }
  }
}

resource "aws_route53_record" "api_certificate_validation" {
  count = var.enable_public_certificate ? 1 : 0

  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_type
  ttl     = 60
  records = [tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_value]
}

resource "aws_acm_certificate_validation" "api" {
  count = var.enable_public_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [aws_route53_record.api_certificate_validation[0].fqdn]
}
