data "aws_availability_zones" "available" {}

locals {
  vpc_cidr_block = "10.0.0.0/16"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"

  name           = "example"
  cidr           = local.vpc_cidr_block
  azs            = data.aws_availability_zones.available.names
  public_subnets = [cidrsubnet(local.vpc_cidr_block, 8, 0), cidrsubnet(local.vpc_cidr_block, 8, 1), cidrsubnet(local.vpc_cidr_block, 8, 2)]
}