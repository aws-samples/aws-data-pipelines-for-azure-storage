terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90.0"
    }
  }
}
provider "aws" {
  profile = "azurecid"
  region  = var.Region
  default_tags {
    tags = {
      Provisioner = "Terraform"
      Owner       = var.OwnerTag
      Environment = var.EnvironmentTag
      Solution    = "azs3copy"
    }
  }
}