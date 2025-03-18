terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90.0"
    }
  }
}
provider "aws" {
  profile = "buw-dev"
  region  = var.Region
  default_tags {
    tags = {
      Customer    = var.OwnerTag
      Environment = var.EnvironmentTag
      Provisioner = "Terraform"
      Solution    = "cidazure"
    }
  }
}