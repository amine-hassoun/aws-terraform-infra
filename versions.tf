terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

 backend "s3" {
   bucket         = "amine-hassoun-aws-terraform-infra-state"
   key            = "aws-terraform-infra/terraform.tfstate"
   region         = "eu-west-3"
   dynamodb_table = "terraform-locks"
   encrypt        = true
  }
}

provider "aws" {
  region  = "eu-west-3"
}
# CI/CD pipeline verified 2026-09-26
