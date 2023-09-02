terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.10"
    }
  }
}
provider "aws" {
  profile = "azurecid"
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