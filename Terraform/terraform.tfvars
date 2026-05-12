# ──────────────────────────────────────────
# General
# ──────────────────────────────────────────
aws_region   = "ap-southeast-1"
name_project = "devsecops"
Environment  = "Development"
account_id   = "492462084314"

# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
cidr_vpc        = "172.16.0.0/16"
azs             = ["ap-southeast-1a", "ap-southeast-1b"]
public_subnets  = ["172.16.0.0/24", "172.16.2.0/24"]
private_subnets = ["172.16.1.0/24", "172.16.3.0/24"]

# ──────────────────────────────────────────
# Accounts
# ──────────────────────────────────────────
approved_regions      = "ap-southeast-1"
dev_account_id        = "486554618535"
staging_account_id    = "492462084314"
production_account_id = "492462084314"

# ──────────────────────────────────────────
# GitHub
# ──────────────────────────────────────────
github_org  = "biniter1"
github_repo = "DACN"
