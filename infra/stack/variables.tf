# ---- Identity / naming ------------------------------------------------------
variable "project" {
  description = "Project name; every resource is named <project>-<environment>-<component>."
  type        = string
  default     = "guestbook"
}

variable "environment" {
  description = "Environment name (dev, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "mohamed.samir"
}

variable "repository" {
  description = "Repository tag."
  type        = string
  default     = "cloud-devops-assessment"
}

variable "cost_center" {
  description = "Cost allocation tag."
  type        = string
  default     = "devops-assessment"
}

# ---- Network ----------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "az_count" {
  description = "Availability zones to span."
  type        = number
  default     = 2
}

variable "nat_gateway_mode" {
  description = "none | single | per_az. See modules/network."
  type        = string
  default     = "none"
}

variable "flow_logs_retention_days" {
  description = "VPC flow log retention (0 disables)."
  type        = number
  default     = 7
}

# ---- Application ------------------------------------------------------------
variable "image_tag" {
  description = "API image tag to deploy; CI passes the commit SHA."
  type        = string
}

variable "ecr_repository_name" {
  description = "Shared ECR repository created by infra/bootstrap."
  type        = string
  default     = "guestbook-api"
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Autoscaling minimum."
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Autoscaling maximum."
  type        = number
  default     = 3
}

variable "container_insights" {
  description = "Enable ECS Container Insights."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Application log retention."
  type        = number
  default     = 14
}

# ---- Database ---------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "RDS Multi-AZ standby (HA)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "RDS automated backup / PITR window."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Protect the DB from deletion."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on destroy."
  type        = bool
  default     = true
}

variable "db_performance_insights" {
  description = "Enable RDS Performance Insights."
  type        = bool
  default     = false
}

variable "db_max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling (0 = off)."
  type        = number
  default     = 0
}

# ---- Edge -------------------------------------------------------------------
variable "enable_waf" {
  description = "Attach AWS WAF to CloudFront."
  type        = bool
  default     = false
}

# ---- Backup -----------------------------------------------------------------
variable "backup_daily_retention_days" {
  description = "AWS Backup daily retention."
  type        = number
  default     = 7
}

variable "backup_weekly_retention_days" {
  description = "AWS Backup weekly retention (0 = no weekly rule)."
  type        = number
  default     = 0
}

variable "enable_cross_region_backup" {
  description = "Copy backups to backup_copy_region."
  type        = bool
  default     = false
}

variable "backup_copy_region" {
  description = "DR region for backup copies."
  type        = string
  default     = "eu-central-1"
}

variable "enable_backup_vault_lock" {
  description = "WORM-lock the backup vault."
  type        = bool
  default     = false
}

# ---- Monitoring -------------------------------------------------------------
variable "alert_emails" {
  description = "Emails that receive CloudWatch alarms and backup failures."
  type        = list(string)
  default     = []
}
