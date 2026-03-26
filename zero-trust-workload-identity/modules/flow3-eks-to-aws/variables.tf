variable "aws_region" {
  type = string
  description = "Region của project"
  default = "ap-southeast-1"
}
variable "production_account_id" {
  type = string
  description = "Id của account production"
}
variable "cluster_name" {
  type = string
  description = "Tên của cluster"
  default = "online-boutique"
}