resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db"
  description = "Isolated data-tier subnets"
  subnet_ids  = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-postgres${var.engine_version}"
  family      = "postgres${var.engine_version}"
  description = "Hardened defaults for ${var.name_prefix}"

  parameter {
    name  = "rds.force_ssl"
    value = "1" # reject any non-TLS client connection
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500 ms
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username
  # RDS generates the password, stores it in Secrets Manager (encrypted with
  # our key) and rotates it; it never appears in code, CI logs or tfstate.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb > 0 ? var.max_allocated_storage_gb : null
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period  = var.backup_retention_days
  backup_window            = "01:00-01:30"
  maintenance_window       = "sun:02:00-sun:03:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = var.skip_final_snapshot

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-postgres-final"

  iam_database_authentication_enabled = true

  performance_insights_enabled          = var.performance_insights
  performance_insights_kms_key_id       = var.performance_insights ? var.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights ? 7 : null

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = !var.deletion_protection

  tags = {
    Name   = "${var.name_prefix}-postgres"
    backup = var.backup_plan_selected ? "true" : "false"
  }
}
