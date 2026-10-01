variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "deletion_window_days" {
  description = "Waiting period before a scheduled key deletion takes effect."
  type        = number
  default     = 7
}
