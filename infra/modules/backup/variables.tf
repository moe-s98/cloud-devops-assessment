variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Only resources whose Environment tag matches are selected."
  type        = string
}

variable "daily_retention_days" {
  description = "Retention of daily recovery points."
  type        = number
  default     = 7
}

variable "weekly_retention_days" {
  description = "Retention of weekly recovery points (0 disables the weekly rule)."
  type        = number
  default     = 35
}

variable "enable_cross_region_copy" {
  description = "Copy every recovery point to a vault in the copy_region provider's region (DR)."
  type        = bool
  default     = false
}

variable "enable_vault_lock" {
  description = "WORM protection: recovery points cannot be deleted before min retention, even by admins."
  type        = bool
  default     = false
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the backup key can be deleted."
  type        = number
  default     = 7
}
