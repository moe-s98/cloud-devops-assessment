output "vault_name" {
  description = "Primary backup vault name."
  value       = aws_backup_vault.this.name
}

output "plan_id" {
  description = "Backup plan ID."
  value       = aws_backup_plan.this.id
}

output "backup_role_arn" {
  description = "IAM role used by AWS Backup (also used for on-demand jobs / restores)."
  value       = aws_iam_role.backup.arn
}
