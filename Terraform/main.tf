terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35.1"
    }
  }

  backend "s3" {
    bucket         = "company-terraform-state-demo-project"
    key            = "prod/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-lock-demo-project"
  }
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  name_project    = var.name_project
  Environment     = var.Environment
  cidr_vpc        = var.cidr_vpc
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# ──────────────────────────────────────────
# IAM Roles (EKS cluster role + node role)
# ──────────────────────────────────────────
module "iam" {
  source       = "./modules/identity/iam"
  name_project = var.name_project
}

# ──────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────
module "security_group" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id
}

# ──────────────────────────────────────────
# KMS Keys (EKS secrets + CloudWatch logs)
# ──────────────────────────────────────────
module "kms" {
  source     = "./modules/kms"
  account_id = var.account_id
  aws_region = var.aws_region
}

# ──────────────────────────────────────────
# EKS Cluster (Control Plane)
# ──────────────────────────────────────────
module "eks_cluster" {
  source = "./modules/compute/eks_cluster"

  name_project         = var.name_project
  Environment          = var.Environment
  private_subnets      = module.vpc.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_sg_id       = module.security_group.eks_node_sg_id
  kms_key_arn          = module.kms.eks_key_arn

  depends_on = [module.kms]
}

# ──────────────────────────────────────────
# EKS Node Group (Worker Nodes)
# ──────────────────────────────────────────
module "eks_node" {
  source = "./modules/compute/eks_node"

  Environment        = var.Environment
  private_subnets    = module.vpc.private_subnet_ids
  eks_cluster_name   = module.eks_cluster.cluster_name
  eks_node_role_arn  = module.iam.eks_node_role_arn
  eks_node_role_name = module.iam.eks_node_role_name

  depends_on = [module.eks_cluster]
}

# ──────────────────────────────────────────
# CloudWatch Logs & Security Alarms
# ──────────────────────────────────────────
module "cloudwatch" {
  source = "./modules/cloudwacth"

  cluster_name          = module.eks_cluster.cluster_name
  eks_kms_key_arn       = module.kms.eks_key_arn
  cloudwatch_kms_key_id = module.kms.cloudwatch_key_id

  depends_on = [module.eks_cluster, module.kms]
}

# ──────────────────────────────────────────
# IAM Identity Center (SSO) — 6 permission sets
# ──────────────────────────────────────────
module "sso" {
  source = "./modules/identity/sso"

  approved_regions      = var.aws_region
  dev_account_id        = var.dev_account_id
  staging_account_id    = var.staging_account_id
  production_account_id = var.production_account_id
}

# ──────────────────────────────────────────
# IRSA Flow 1 — GitHub Actions → ECR
# OIDC provider + ECR repositories + push role
# ──────────────────────────────────────────
module "github_ecr" {
  source = "./modules/IRSA/GITHUB-ECR"

  github_org            = var.github_org
  github_repo           = var.github_repo
  aws_region            = var.aws_region
  production_account_id = var.production_account_id
}

# ──────────────────────────────────────────
# IRSA Flow 2 — GitHub Actions → EKS
# Deploy role (EKS describe only, SLSA L2)
# ──────────────────────────────────────────
module "github_eks" {
  source = "./modules/IRSA/GITHUB-EKS"

  github_org            = var.github_org
  github_repo           = var.github_repo
  aws_region            = var.aws_region
  production_account_id = var.production_account_id
  eks_cluster_name      = module.eks_cluster.cluster_name
  github_arn            = module.github_ecr.github

  depends_on = [module.github_ecr, module.eks_cluster]
}

# ──────────────────────────────────────────
# EKS Pod Identity — per-service workload roles
# Flow 3: EKS workloads → AWS services (least-privilege)
# ──────────────────────────────────────────
module "pod_identity" {
  source = "./modules/Pod_Identity"

  cluster_name          = module.eks_cluster.cluster_name
  aws_region            = var.aws_region
  production_account_id = var.production_account_id

  depends_on = [module.eks_cluster]
}

# ──────────────────────────────────────────
# AWS Organizations — OUs, Member Accounts & SCPs
# ──────────────────────────────────────────
module "organization" {
  source = "./modules/organization"

  approved_regions      = var.aws_region
  dev_account_id        = var.dev_account_id
  staging_account_id    = var.staging_account_id
  production_account_id = var.production_account_id
}
