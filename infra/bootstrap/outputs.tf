output "state_bucket" {
  description = "S3 bucket for environment Terraform state."
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_url" {
  description = "Shared ECR repository for the API image."
  value       = aws_ecr_repository.api.repository_url
}

output "ci_role_arns" {
  description = "Roles assumed by the GitLab CI users."
  value       = { for k, r in aws_iam_role.ci : k => r.arn }
}

output "ci_user_names" {
  description = "IAM users whose access keys go into GitLab CI/CD variables."
  value       = { for k, u in aws_iam_user.ci : k => u.name }
}
