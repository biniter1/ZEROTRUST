variable "cluster_name" {
  type = string
}

variable "eks_kms_key_arn" {
  type        = string
  description = "KMS key ARN for CloudWatch log group encryption"
}

variable "cloudwatch_kms_key_id" {
  type        = string
  description = "KMS key ID for SNS topic encryption"
}