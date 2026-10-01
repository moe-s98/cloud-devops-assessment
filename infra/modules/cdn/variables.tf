variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "alb_arn" {
  description = "Internal ALB that serves /api/* (via CloudFront VPC origin)."
  type        = string
}

variable "origin_verify_header_value" {
  description = "Secret header value CloudFront sends to the ALB."
  type        = string
  sensitive   = true
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 = NA + Europe, cheapest)."
  type        = string
  default     = "PriceClass_100"
}

variable "enable_waf" {
  description = "Attach a WAFv2 web ACL (managed rules + per-IP rate limit). ~USD 6+/month."
  type        = bool
  default     = false
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per 5 minutes per client IP before WAF blocks."
  type        = number
  default     = 1000
}

variable "noncurrent_version_days" {
  description = "Days to keep previous versions of frontend objects (rollback window)."
  type        = number
  default     = 30
}

variable "alb_dns_name" {
  description = "Internal ALB DNS name (origin domain for the VPC origin)."
  type        = string
}
