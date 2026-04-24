# ──────────────────────────────────────────
# General
# ──────────────────────────────────────────
variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "ap-southeast-2"
}

variable "name_project" {
  type        = string
  description = "Name of the project"
  default     = "devsecops"
}

variable "Environment" {
  type        = string
  description = "Environment (Development, Staging, Production)"
  default     = "Development"
}
variable "account_id" {
  type = string
}
# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
variable "cidr_vpc" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "172.16.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones"
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["172.16.0.0/24", "172.16.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["172.16.1.0/24", "172.16.3.0/24"]
}



variable "approved_regions" {
  type = string
}
variable "dev_account_id" {
  type = string
}
variable "staging_account_id" {
  type = string
}
variable "production_account_id" {
  type = string
}

# ──────────────────────────────────────────
# GitHub
# ──────────────────────────────────────────
variable "github_org" {
  type        = string
  description = "GitHub organization name (e.g. my-org)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (e.g. my-repo)"
}