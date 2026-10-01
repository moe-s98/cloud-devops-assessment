variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name passed to the app (APP_ENV)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Private subnets for the internal ALB."
  type        = list(string)
}

variable "task_subnet_ids" {
  description = "Subnets for the Fargate tasks."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Give tasks a public IP for egress (only when there is no NAT gateway). Inbound is still ALB-only via the SG."
  type        = bool
}

variable "alb_security_group_id" {
  description = "ALB security group."
  type        = string
}

variable "app_security_group_id" {
  description = "Task security group."
  type        = string
}

variable "image_repository_url" {
  description = "ECR repository URL of the API image."
  type        = string
}

variable "image_tag" {
  description = "Immutable image tag to deploy (the git commit SHA)."
  type        = string
}

variable "container_port" {
  description = "Port the API listens on."
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "Task vCPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory in MiB."
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Minimum running tasks (autoscaling floor)."
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Maximum running tasks (autoscaling ceiling)."
  type        = number
  default     = 3
}

variable "cpu_target_percent" {
  description = "Target average CPU for target-tracking scaling."
  type        = number
  default     = 60
}

variable "requests_per_task_target" {
  description = "Target ALB requests per task per minute for target-tracking scaling."
  type        = number
  default     = 500
}

variable "db_host" {
  description = "Database hostname."
  type        = string
}

variable "db_port" {
  description = "Database port."
  type        = number
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_username" {
  description = "Database username."
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB credentials JSON."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the log group and for decrypting the DB secret."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the API log group."
  type        = number
  default     = 14
}

variable "origin_verify_header_value" {
  description = "Shared secret CloudFront adds as X-Origin-Verify; the ALB rejects requests without it."
  type        = string
  sensitive   = true
}

variable "container_insights" {
  description = "Enable ECS Container Insights (extra CloudWatch metrics, small cost)."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect the ALB from deletion."
  type        = bool
  default     = false
}
