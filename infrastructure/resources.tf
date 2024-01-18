# Big thanks to Alex Hyett for his post on setting this up!
# https://www.alexhyett.com/terraform-s3-static-website-hosting

locals {
  domain_name = "theminimalmixologist.com"
}

# www bucket

resource "aws_s3_bucket" "www" {
  bucket = "www.${local.domain_name}"
}

resource "aws_s3_bucket_website_configuration" "www" {
  bucket = aws_s3_bucket.www.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_public_access_block" "www" {
  bucket = aws_s3_bucket.www.bucket

  block_public_acls = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "www" {
  bucket = aws_s3_bucket.www.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "www" {
  depends_on = [
    aws_s3_bucket_ownership_controls.www,
    aws_s3_bucket_public_access_block.www,
  ]
  bucket = aws_s3_bucket.www.bucket
  acl = "public-read"
}

resource "aws_s3_bucket_policy" "www_public_access" {
  depends_on = [aws_s3_bucket_acl.www]
  bucket = aws_s3_bucket.www.bucket
  policy = templatefile("templates/s3-policy.json", { bucket = "www.${local.domain_name}" })
}

# Root bucket

resource "aws_s3_bucket" "root" {
  bucket = local.domain_name
}

resource "aws_s3_bucket_website_configuration" "root" {
  bucket = aws_s3_bucket.root.bucket
  redirect_all_requests_to {
    host_name = "www.${local.domain_name}"
    protocol = "https"
  }
}

# SSL cert

resource "aws_acm_certificate" "ssl_cert" {
  provider = aws.acm_provider
  domain_name = local.domain_name
  subject_alternative_names = ["*.${local.domain_name}"]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation for certificate

resource "aws_route53_record" "dns_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl_cert.domain_validation_options : dvo.domain_name => {
      name = dvo.resource_record_name
      record = dvo.resource_record_value
      type = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  allow_overwrite = true
  name = each.value.name
  records = [each.value.record]
  ttl = 60
  type = each.value.type
}

resource "aws_acm_certificate_validation" "cert_validation" {
  provider = aws.acm_provider
  certificate_arn = aws_acm_certificate.ssl_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.dns_validation : record.fqdn]
}

# CloudFront distributions

data "aws_cloudfront_cache_policy" "default_cache" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "www" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.www.website_endpoint
    origin_id = "S3-www.${local.domain_name}"

    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true
  is_ipv6_enabled = true
  default_root_object = aws_s3_bucket_website_configuration.www.index_document[0].suffix

  aliases = ["www.${local.domain_name}"]

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "S3-www.${local.domain_name}"
    cache_policy_id = data.aws_cloudfront_cache_policy.default_cache.id
    viewer_protocol_policy = "redirect-to-https"
    min_ttl = 31536000
    default_ttl = 31536000
    max_ttl = 31536000
    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}

resource "aws_cloudfront_distribution" "root" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.root.website_endpoint
    origin_id = "S3-.${local.domain_name}"
    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true
  is_ipv6_enabled = true

  aliases = [local.domain_name]

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "S3-.${local.domain_name}"
    cache_policy_id = data.aws_cloudfront_cache_policy.default_cache.id
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 86400
    max_ttl = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}

# Route 53 records

# Note: I don't want Terraform to manage the zone since re-creating it would
# force me to manually update my DNS provider.
data "aws_route53_zone" "main" {
  name = local.domain_name
}

resource "aws_route53_record" "root-a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = local.domain_name
  type = "A"

  alias {
    name = aws_cloudfront_distribution.root.domain_name
    zone_id = aws_cloudfront_distribution.root.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root-aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = local.domain_name
  type = "AAAA"

  alias {
    name = aws_cloudfront_distribution.root.domain_name
    zone_id = aws_cloudfront_distribution.root.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www-a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = "www.${local.domain_name}"
  type = "A"

  alias {
    name = aws_cloudfront_distribution.www.domain_name
    zone_id = aws_cloudfront_distribution.www.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www-aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = "www.${local.domain_name}"
  type = "AAAA"

  alias {
    name = aws_cloudfront_distribution.www.domain_name
    zone_id = aws_cloudfront_distribution.www.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = local.domain_name
  type = "MX"
  ttl = 300
  records = [
    "10 mx.zoho.com",
    "20 mx2.zoho.com",
    "50 mx3.zoho.com",
  ]
}

resource "aws_route53_record" "zoho-txt" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = local.domain_name
  type = "TXT"
  ttl = 300
  records = [
    "zoho-verification=zb46711250.zmverify.zoho.com",
    "v=spf1 include:zoho.com ~all",
  ]
}

resource "aws_route53_record" "zoho-txt-subdomain" {
  zone_id = data.aws_route53_zone.main.zone_id
  name = "zmail._domainkey.${local.domain_name}"
  type = "TXT"
  ttl = 300
  records = [
    "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCohzsdXrwHeKpiPoWPJAcFI8jT/Pto/U3Ir11+AwrfpKPrzgW0eCjPhBoJNt4w6pGJmP7DUJ/ZNvgy6mjJVKgtUM1XpqUVO70fv+l5gqt4bRNUsjPmVDnZzt35rrNOZ53aYr32u9hWfX7FVa6kSbO2lPOlgmBPKjYHiUbReDmIcwIDAQAB",
  ]
}
