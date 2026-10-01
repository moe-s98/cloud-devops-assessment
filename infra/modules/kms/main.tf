# Customer-managed key for data at rest in this environment: RDS storage and
# its master-user secret, CloudWatch log groups and the SNS alert topic.
# (Backups use a separate key in the backup module, so a compromise of one
# does not expose the other.)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

data "aws_iam_policy_document" "key" {
  # Delegate to IAM: identities in this account get access only via their IAM policies.
  statement {
    sid       = "AccountRootDelegatesToIam"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogsEncryptOwnLogGroups"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/${var.name_prefix}/*"]
    }
  }

  # CloudWatch alarms and EventBridge publish to the encrypted SNS topic.
  statement {
    sid       = "AlarmsAndEventsPublishToEncryptedSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} data-at-rest key"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_days
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-main"
  target_key_id = aws_kms_key.this.key_id
}
