locals {
  name_prefix = "${var.project}-${var.environment}"

  default_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    Repository  = var.repository
    CostCenter  = var.cost_center
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = local.default_tags
  }
}

# CloudFront-scoped WAF must be created in us-east-1.
provider "aws" {
  alias      = "us_east_1"
  region     = "us-east-1"
  sts_region = var.region
  default_tags {
    tags = local.default_tags
  }
}

# Destination region for cross-region backup copies (DR).
# STS calls (CI role assumption) stay on the primary region's endpoint: the
# account's organization SCP denies AssumeRole through some regional endpoints.
provider "aws" {
  alias      = "copy_region"
  region     = var.backup_copy_region
  sts_region = var.region
  default_tags {
    tags = local.default_tags
  }
}
