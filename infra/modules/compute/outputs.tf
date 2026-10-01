output "alb_arn" {
  description = "Internal ALB ARN (CloudFront VPC origin target)."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Internal ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch metrics."
  value       = aws_lb_target_group.api.arn_suffix
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.api.name
}

output "log_group_name" {
  description = "API log group."
  value       = aws_cloudwatch_log_group.api.name
}
