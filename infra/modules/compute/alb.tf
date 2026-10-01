# Internal ALB: no public IP; CloudFront reaches it through a VPC origin.
resource "aws_lb" "this" {
  name                       = "${var.name_prefix}-alb"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.alb_subnet_ids
  security_groups            = [var.alb_security_group_id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 30
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.name_prefix}-api"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 15

  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Anything that did not come through our CloudFront distribution is refused.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_header_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
