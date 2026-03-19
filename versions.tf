terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.20"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }

  backend "s3" {
    bucket = "baobeier-terraform-states"
    key    = "aws-terraform-vpn"
    region = "ap-southeast-2"
  }
}
