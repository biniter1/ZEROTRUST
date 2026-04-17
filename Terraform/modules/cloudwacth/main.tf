resource "aws_cloudwatch_log_group" "eks" {
  name = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90

  kms_key_id = aws_kms_key.eks.arn

}

resource "aws_cloudwatch_metric_alarm" "anonymous_auth" {
  alarm_name          = "eks-anonymous-auth-attempt"
  alarm_description   = "Anonymous authentication attempt to K8s API"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  statistic           = "Sum"

  metric_name = "AnonymousAuthAttempt"
  namespace   = "ZeroTrust/EKS"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}

# Alert khi có unauthorized action
resource "aws_cloudwatch_metric_alarm" "unauthorized_access" {
  alarm_name          = "eks-unauthorized-access"
  alarm_description   = "Unauthorized K8s API access attempt"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5    # 5 lần trong 5 phút = alert
  period              = 300
  statistic           = "Sum"

  metric_name = "UnauthorizedAccess"
  namespace   = "ZeroTrust/EKS"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}

# SNS Topic để gửi alert
resource "aws_sns_topic" "security_alerts" {
  name              = "eks-security-alerts"
  kms_master_key_id = aws_kms_key.cloudwatch.id
}