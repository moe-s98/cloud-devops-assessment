output "distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_domain" {
  description = "Public HTTPS domain of the application."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "frontend_bucket" {
  description = "S3 bucket holding the static frontend."
  value       = aws_s3_bucket.frontend.bucket
}
