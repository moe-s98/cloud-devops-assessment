variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "app_port" {
  description = "Port the API container listens on."
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}
