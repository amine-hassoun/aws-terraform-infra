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
  }

 backend "s3" {
   bucket         = "amine-hassoun-aws-terraform-infra-state"
   key            = "aws-terraform-infra/terraform.tfstate"
   region         = "eu-west-3"
   dynamodb_table = "terraform-locks"
   encrypt        = true
   profile	  = "terraform-deploy"
  }
}

provider "aws" {
  region  = "eu-west-3"
  profile = "terraform-deploy"
}
