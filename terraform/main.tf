terraform {
  backend "s3" {
    bucket = "hi1280-tfstate-main"
    key    = "redash.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_caller_identity" "current" {}