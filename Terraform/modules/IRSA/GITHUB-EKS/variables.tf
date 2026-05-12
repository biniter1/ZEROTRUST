variable "github_org" {
  type = string
  description = "Org của repo github"
}
variable "github_repo" {
  type = string
  description = "Link đến repo github"
}
variable "aws_region" {
  type = string
  description = "Region của project"
}
variable "production_account_id" {
  type = string
  description = "Id account của production"
}
variable "eks_cluster_name" {
  type = string
  description = "Tên cluster eks"
}
variable "github_arn"{
  type = string
  description = "ARN của OIDC provider"
}