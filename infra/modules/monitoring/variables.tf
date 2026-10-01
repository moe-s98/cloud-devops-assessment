variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "alert_emails" {
  description = "Email addresses subscribed to alerts (each must confirm the SNS subscription)."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS key for the SNS topic."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch dimension)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch dimension)."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name."
  type        = string
}

variable "api_log_group_name" {
  description = "API log group (JSON logs) for the error metric filter."
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance identifier."
  type        = string
}

variable "thresholds" {
  description = "Alarm thresholds."
  type = object({
    target_5xx_per_5min = number
    p95_latency_seconds = number
    ecs_cpu_percent     = number
    ecs_memory_percent  = number
    rds_cpu_percent     = number
    rds_free_storage_gb = number
    app_errors_per_5min = number
  })
  default = {
    target_5xx_per_5min = 5
    p95_latency_seconds = 1
    ecs_cpu_percent     = 80
    ecs_memory_percent  = 80
    rds_cpu_percent     = 80
    rds_free_storage_gb = 2
    app_errors_per_5min = 5
  }
}
