locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  alb_dims      = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  ecs_dims      = { ClusterName = var.ecs_cluster_name, ServiceName = var.ecs_service_name }
  rds_dims      = { DBInstanceIdentifier = var.db_instance_id }
  metric_ns     = "Guestbook/${var.name_prefix}"
}

# ---- Application / ALB ------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "API returned >= ${var.thresholds.target_5xx_per_5min} 5xx responses in 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dims
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.thresholds.target_5xx_per_5min
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name_prefix}-api-latency-p95"
  alarm_description   = "p95 API latency above ${var.thresholds.p95_latency_seconds}s for 3 of 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dims
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.thresholds.p95_latency_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name          = "${var.name_prefix}-api-no-healthy-targets"
  alarm_description   = "No healthy API tasks behind the load balancer: the API is down."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.alb_dims
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---- Log-based metric: ERROR lines in the API's JSON logs --------------------
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.name_prefix}-api-errors"
  log_group_name = var.api_log_group_name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = local.metric_ns
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.name_prefix}-api-error-logs"
  alarm_description   = "API logged >= ${var.thresholds.app_errors_per_5min} ERROR lines in 5 minutes."
  namespace           = local.metric_ns
  metric_name         = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.thresholds.app_errors_per_5min
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

# ---- ECS ----------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.name_prefix}-ecs-cpu-high"
  alarm_description   = "API service CPU above ${var.thresholds.ecs_cpu_percent}% for 10 minutes (autoscaling at max?)."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.thresholds.ecs_cpu_percent
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${var.name_prefix}-ecs-memory-high"
  alarm_description   = "API service memory above ${var.thresholds.ecs_memory_percent}% for 10 minutes."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.thresholds.ecs_memory_percent
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---- RDS ----------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "Database CPU above ${var.thresholds.rds_cpu_percent}% for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.rds_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.thresholds.rds_cpu_percent
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  alarm_description   = "Database free storage below ${var.thresholds.rds_free_storage_gb} GB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = local.rds_dims
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.thresholds.rds_free_storage_gb * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---- AWS Backup job failures -> same alert topic ------------------------------
resource "aws_cloudwatch_event_rule" "backup_failed" {
  name        = "${var.name_prefix}-backup-job-failed"
  description = "AWS Backup / copy job failed, aborted or expired."
  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change", "Copy Job State Change"]
    detail      = { state = ["FAILED", "ABORTED", "EXPIRED"] }
  })
}

resource "aws_cloudwatch_event_target" "backup_failed" {
  rule = aws_cloudwatch_event_rule.backup_failed.name
  arn  = aws_sns_topic.alerts.arn
}
