variable "name_prefix" {
  description = "Prefix for resource names, e.g. guestbook-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (min 2: RDS and the ALB require it)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway_mode" {
  description = "none = app tasks run in public subnets (cheapest), single = one shared NAT, per_az = one NAT per AZ (HA)."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be none, single or per_az."
  }
}

variable "flow_logs_retention_days" {
  description = "Retention for VPC flow logs; 0 disables flow logs."
  type        = number
  default     = 7
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the flow-log log group."
  type        = string
}
