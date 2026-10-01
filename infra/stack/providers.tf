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

# Destination region for cross-region backup copies (DR). When DR copies are
# off it points at the primary region, so the stack never touches (or needs
# permissions in) a second region it does not use.
provider "aws" {
  alias  = "copy_region"
  region = var.enable_cross_region_backup ? var.backup_copy_region : var.region
  default_tags {
    tags = local.default_tags
  }
}
