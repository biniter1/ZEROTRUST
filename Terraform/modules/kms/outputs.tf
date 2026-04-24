output "eks_key_arn" {
  description = "ARN of the KMS key for EKS secret encryption"
  value       = aws_kms_key.eks.arn
}

output "cloudwatch_key_arn" {
  description = "ARN of the KMS key for CloudWatch log encryption"
  value       = aws_kms_key.cloudwatch.arn
}

output "cloudwatch_key_id" {
  description = "ID of the KMS key for SNS/CloudWatch encryption"
  value       = aws_kms_key.cloudwatch.id
}
