data "aws_region" "current" {}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/${var.name_prefix}/ecs/api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${var.image_repository_url}:${var.image_tag}"
    essential = true
    user      = "10001"

    readonlyRootFilesystem = true
    linuxParameters        = { capabilities = { drop = ["ALL"] } }

    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

    environment = [
      { name = "APP_ENV", value = var.environment },
      { name = "APP_VERSION", value = var.image_tag },
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_PORT", value = tostring(var.db_port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username },
      { name = "DB_SSLMODE", value = "require" },
    ]

    # Injected by ECS at start from Secrets Manager; never in the image or env file.
    secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" }]

    healthCheck = {
      command     = ["CMD", "python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:${var.container_port}/api/health', timeout=2).status == 200 else 1)"]
      interval    = 15
      timeout     = 3
      retries     = 3
      startPeriod = 20
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name                              = "${var.name_prefix}-api"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.min_tasks
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30
  enable_execute_command            = false
  propagate_tags                    = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # A deployment whose tasks fail to become healthy is rolled back to the
  # last steady-state task definition automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.task_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  # Autoscaling owns the running count after creation.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.from_cloudfront]
}

# ---- Autoscaling: CPU and request-rate target tracking ----------------------
resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name_prefix}-api-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  resource_id        = aws_appautoscaling_target.api.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 120
    scale_out_cooldown = 30
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name_prefix}-api-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  resource_id        = aws_appautoscaling_target.api.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_task_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 30
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.api.arn_suffix}"
    }
  }
}
