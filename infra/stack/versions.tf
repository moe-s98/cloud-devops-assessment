terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial config: bucket and key come from envs/<env>/backend.hcl or CI
  # (-backend-config), so one stack serves every environment.
  backend "s3" {
    encrypt      = true
    use_lockfile = true # S3-native state locking, no DynamoDB table
  }
}
