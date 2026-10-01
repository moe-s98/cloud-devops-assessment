output "app_url" {
  description = "Public HTTPS URL of the application."
  value       = "https://${module.cdn.distribution_domain}"
}

output "frontend_bucket" {
  description = "Bucket CI syncs the frontend into."
  value       = module.cdn.frontend_bucket
}

output "cloudfront_distribution_id" {
  description = "Distribution to invalidate after a frontend deploy."
  value       = module.cdn.distribution_id
}

output "ecs_cluster" {
  description = "ECS cluster name."
  value       = module.compute.cluster_name
}

output "ecs_service" {
  description = "ECS service name."
  value       = module.compute.service_name
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = module.database.instance_id
}

output "backup_vault" {
  description = "AWS Backup vault name."
  value       = module.backup.vault_name
}

output "backup_role_arn" {
  description = "Role for on-demand backup/restore jobs."
  value       = module.backup.backup_role_arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${module.monitoring.dashboard_name}"
}
