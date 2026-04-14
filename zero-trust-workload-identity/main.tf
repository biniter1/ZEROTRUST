terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.38.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "flow1-github-to-ecr" {
  source = "./modules/flow1-github-to-ecr"
  github_org = var.github_org
  github_repo = var.github_repo
  aws_region = var.region
  production_account_id = var.production_account_id
}
module "flow2-github-to-k8s" {
  source = "./modules/flow2-github-to-k8s"
  github_arn = module.flow1-github-to-ecr.github
  github_org = var.github_org
  github_repo = var.github_repo
  aws_region = var.region
  production_account_id = var.production_account_id
  eks_cluster_name = var.eks_cluster_name
}
module "flow3-eks-to-aws" {
  source = "./modules/flow3-eks-to-aws"
  aws_region = var.region
  production_account_id = var.production_account_id
  cluster_name = var.eks_cluster_name
}
