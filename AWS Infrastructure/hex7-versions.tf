# Terraform Block
terraform {
  required_version = ">= 1.13" # which means any version equal & above 1.14 like 1.15, 1.16 etc and < 1.xx
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }        
  }
}

# Provider Block
provider "aws" {
  region  = var.aws_region
  profile = "default"
}
/*
Note-1:  AWS Credentials Profile (profile = "default") configured on your local desktop terminal  
$HOME/.aws/credentials
*/