variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Isolated data-tier subnets (at least two AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group that allows PostgreSQL from the app tier only."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for storage, Performance Insights and the master-user secret."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial storage in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling in GB (0 disables autoscaling)."
  type        = number
  default     = 0
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "guestbook"
}

variable "master_username" {
  description = "Master username (the password is generated and stored by RDS in Secrets Manager)."
  type        = string
  default     = "guestbook_admin"
}

variable "multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup / point-in-time-recovery window in days."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion of the instance."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true only for disposable environments)."
  type        = bool
  default     = true
}

variable "backup_plan_selected" {
  description = "Tag the instance for selection by the AWS Backup plan."
  type        = bool
  default     = true
}

variable "performance_insights" {
  description = "Enable Performance Insights (7-day retention; not available on the smallest burstable classes)."
  type        = bool
  default     = false
}
