# AWS Backup on top of RDS's own 7-day point-in-time recovery:
#   * a dedicated vault with its OWN KMS key (separate from the data key),
#   * daily + weekly snapshots of everything tagged backup=true,
#   * optional cross-region copy (DR) and vault lock (ransomware protection).

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Explicit key policy: account-root delegation to IAM (no direct grants).
data "aws_iam_policy_document" "backup_key" {
  statement {
    sid       = "AccountRootDelegatesToIam"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "backup" {
  description             = "${var.name_prefix} backup vault key"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.backup_key.json
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.name_prefix}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

resource "aws_backup_vault" "this" {
  name          = "${var.name_prefix}-vault"
  kms_key_arn   = aws_kms_key.backup.arn
  force_destroy = !var.enable_vault_lock
}

resource "aws_backup_vault_lock_configuration" "this" {
  count               = var.enable_vault_lock ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.name
  min_retention_days  = var.daily_retention_days
  max_retention_days  = max(var.daily_retention_days, var.weekly_retention_days)
  changeable_for_days = 3 # compliance mode becomes immutable after this grace period
}

# ---- Optional DR copy target in a second region -----------------------------
resource "aws_kms_key" "copy" {
  count                   = var.enable_cross_region_copy ? 1 : 0
  provider                = aws.copy_region
  description             = "${var.name_prefix} backup copy vault key"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.backup_key.json
}

resource "aws_backup_vault" "copy" {
  count         = var.enable_cross_region_copy ? 1 : 0
  provider      = aws.copy_region
  name          = "${var.name_prefix}-vault-dr"
  kms_key_arn   = aws_kms_key.copy[0].arn
  force_destroy = true
}

# ---- Plan -------------------------------------------------------------------
locals {
  rules = merge(
    {
      daily = { schedule = "cron(0 2 * * ? *)", retention = var.daily_retention_days }
    },
    var.weekly_retention_days > 0 ? {
      weekly = { schedule = "cron(0 3 ? * SUN *)", retention = var.weekly_retention_days }
    } : {},
  )
}

resource "aws_backup_plan" "this" {
  name = "${var.name_prefix}-plan"

  dynamic "rule" {
    for_each = local.rules
    content {
      rule_name         = rule.key
      target_vault_name = aws_backup_vault.this.name
      schedule          = rule.value.schedule
      start_window      = 60
      completion_window = 180

      lifecycle {
        delete_after = rule.value.retention
      }

      dynamic "copy_action" {
        for_each = var.enable_cross_region_copy ? [1] : []
        content {
          destination_vault_arn = aws_backup_vault.copy[0].arn
          lifecycle {
            delete_after = rule.value.retention
          }
        }
      }

      recovery_point_tags = { Rule = rule.key }
    }
  }
}

# ---- Selection: anything tagged backup=true -----------------------------------
resource "aws_iam_role" "backup" {
  name = "${var.name_prefix}-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

resource "aws_backup_selection" "tagged" {
  name         = "${var.name_prefix}-tagged"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/backup"
      value = "true"
    }
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}
