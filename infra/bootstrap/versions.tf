terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap creates the remote-state bucket, so its own state is local
  # (chicken-and-egg). It is tiny, rarely changes and holds no secrets.
}
