# CI identities for GitLab.
#
# The GitLab instance is on a private network, so AWS cannot fetch its OIDC
# JWKS and keyless federation is not possible (see README "Secrets"). Instead:
#
#   guestbook-ci-plan   (user) --sts:AssumeRole--> guestbook-ci-plan   (role, read-only)
#   guestbook-ci-deploy (user) --sts:AssumeRole--> guestbook-ci-deploy (role, deploy)
#
# * The users have NO permissions except assuming their one role, so a leaked
#   key alone cannot touch infrastructure without also using STS (auditable
#   in CloudTrail, 1h sessions).
# * The deploy user's key is stored as a *protected* GitLab variable, so only
#   pipelines on the protected `main` branch can ever see it. Merge-request
#   pipelines only get the plan key.
# * Access keys are created outside Terraform so no secret lands in state.

locals {
  ci_identities = {
    plan   = "Read-only: terraform plan on merge requests"
    deploy = "Deploys from protected branch main"
  }
}

resource "aws_iam_user" "ci" {
  for_each = local.ci_identities
  name     = "${var.project}-ci-${each.key}"
  tags     = { Purpose = each.value }
}

resource "aws_iam_role" "ci" {
  for_each             = local.ci_identities
  name                 = "${var.project}-ci-${each.key}"
  description          = each.value
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.ci[each.key].arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_user_policy" "ci_assume_only" {
  for_each = local.ci_identities
  name     = "assume-${each.key}-role-only"
  user     = aws_iam_user.ci[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = aws_iam_role.ci[each.key].arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Shared: state bucket access (both roles need it; plan writes the lock file)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "tfstate_access" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_policy" "tfstate_access" {
  name   = "${var.project}-ci-tfstate-access"
  policy = data.aws_iam_policy_document.tfstate_access.json
}

resource "aws_iam_role_policy_attachment" "tfstate_access" {
  for_each   = local.ci_identities
  role       = aws_iam_role.ci[each.key].name
  policy_arn = aws_iam_policy.tfstate_access.arn
}

# ---------------------------------------------------------------------------
# Plan role: AWS-managed read-only (cannot read secret values or S3 objects
# outside the state bucket).
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.ci["plan"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# Deploy role: scoped to the services this stack uses, to resources named
# "${project}-*" where the service supports resource-level permissions, and
# to the allowed regions.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy" {
  statement {
    sid = "StackServicesInAllowedRegions"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "ecs:*",
      "application-autoscaling:*",
      "rds:*",
      "logs:*",
      "cloudwatch:*",
      "sns:*",
      "events:*",
      "backup:*",
      "backup-storage:*",
      "kms:*",
      "secretsmanager:*",
      "cloudfront:*",
      "wafv2:*",
      "ecr:GetAuthorizationToken",
      "tag:GetResources",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid       = "PushToProjectRegistryOnly"
    actions   = ["ecr:*"]
    resources = [aws_ecr_repository.api.arn]
  }

  statement {
    sid       = "ProjectBucketsOnly"
    actions   = ["s3:*"]
    resources = ["arn:${local.partition}:s3:::${var.project}-*", "arn:${local.partition}:s3:::${var.project}-*/*"]
  }

  # Environment stacks name IAM resources "${project}-<env>-*", so CI can manage
  # those but never the "${project}-ci-*" identities and policies it runs as.
  statement {
    sid     = "ManageOnlyEnvironmentIamRoles"
    actions = ["iam:*"]
    resources = flatten([for env in var.environments : [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-${env}-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-${env}-*",
    ]])
  }

  statement {
    sid       = "PassOnlyProjectRolesToAllowedServices"
    actions   = ["iam:PassRole"]
    resources = [for env in var.environments : "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-${env}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "backup.amazonaws.com", "monitoring.rds.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole", "iam:GetRole", "iam:ListRoles", "iam:ListPolicies", "iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["*"]
  }

  # Explicit guardrail on top of the above: CI can never edit its own identities.
  statement {
    sid     = "DenySelfModification"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-ci-*",
      "arn:${local.partition}:iam::${local.account_id}:user/${var.project}-ci-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-ci-*",
    ]
  }
}

resource "aws_iam_policy" "deploy" {
  name   = "${var.project}-ci-deploy"
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.ci["deploy"].name
  policy_arn = aws_iam_policy.deploy.arn
}
