variable "project" {
  description = "Short project name, used as the prefix of every resource name."
  type        = string
  default     = "guestbook"
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "mohamed.samir"
}

variable "repository" {
  description = "Source repository, recorded as a tag for traceability."
  type        = string
  default     = "cloud-devops-assessment"
}

variable "allowed_regions" {
  description = "Regions the CI deploy role may act in (us-east-1 is needed for CloudFront/WAF)."
  type        = list(string)
  default     = ["eu-north-1", "us-east-1"]
}

variable "environments" {
  description = "Environment names; CI may manage IAM resources prefixed with these."
  type        = list(string)
  default     = ["dev", "prod"]
}
