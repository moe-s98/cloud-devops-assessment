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
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.default_tags
  }
}

# Destination region for cross-region backup copies (DR).
provider "aws" {
  alias  = "copy_region"
  region = var.backup_copy_region
  default_tags {
    tags = local.default_tags
  }
}
