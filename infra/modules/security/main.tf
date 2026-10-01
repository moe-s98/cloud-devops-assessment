# Security groups form a strict chain; each tier accepts traffic only from the
# tier in front of it, referenced by SG ID (not CIDR):
#
#   CloudFront (origin-facing prefix list) --80--> ALB --8000--> app --5432--> db
#
# The ALB is internal and reached through a CloudFront VPC origin, so nothing
# in this VPC accepts connections from the public internet.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Internal ALB: HTTP from CloudFront VPC origin only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "API tasks: app port from the ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-app" }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db"
  description = "PostgreSQL: from API tasks only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-db" }
}

# ---- ALB --------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront origin-facing servers"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To API tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# ---- App --------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "To PostgreSQL"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

# HTTPS out is needed to pull from ECR and call Secrets Manager / CloudWatch
# Logs APIs (no interface endpoints, see README trade-offs).
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs (ECR, Secrets Manager, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---- DB ---------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "From API tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}
# No egress rules on the DB SG: it never initiates connections.
