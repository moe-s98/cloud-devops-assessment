data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  widgets = [
    { title = "Requests / min", metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }]] },
    { title = "5xx (target and ALB)", metrics = [
      ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Sum" }],
      ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
    ] },
    { title = "Latency p50 / p95 (s)", metrics = [
      ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
      ["...", { stat = "p95" }],
    ] },
    { title = "Healthy tasks", metrics = [["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "Minimum" }]] },
    { title = "ECS CPU / memory %", metrics = [
      ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
      [".", "MemoryUtilization", ".", ".", ".", "."],
    ] },
    { title = "App ERROR log lines", metrics = [[local.metric_ns, "AppErrorCount", { stat = "Sum" }]] },
    { title = "RDS CPU %", metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id]] },
    { title = "RDS connections", metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id]] },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"
  dashboard_body = jsonencode({
    widgets = concat(
      [for i, w in local.widgets : {
        type   = "metric"
        x      = (i % 3) * 8
        y      = floor(i / 3) * 6
        width  = 8
        height = 6
        properties = {
          title   = w.title
          region  = local.region
          metrics = w.metrics
          period  = 60
          view    = "timeSeries"
          stat    = "Average"
        }
      }],
      [{
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Recent API errors"
          region = local.region
          query  = "SOURCE '${var.api_log_group_name}' | fields ts, level, method, path, status, msg | filter level = 'ERROR' | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }],
      [{
        type   = "alarm"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.target_5xx.arn,
            aws_cloudwatch_metric_alarm.latency_p95.arn,
            aws_cloudwatch_metric_alarm.no_healthy_targets.arn,
            aws_cloudwatch_metric_alarm.app_errors.arn,
            aws_cloudwatch_metric_alarm.ecs_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_storage.arn,
          ]
        }
      }],
    )
  })
}
