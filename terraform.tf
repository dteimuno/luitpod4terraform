terraform {
  required_version = ">= 1.0.0"
  backend "s3" {
    bucket         = "luitpurple2024pod4backend"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"

  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}