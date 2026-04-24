resource "aws_eks_addon" "pod_identity" {
  cluster_name = var.cluster_name
  addon_name = "eks-pod-identity-agent"
  addon_version = "v1.3.2-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values = jsonencode({
    replicaCount = 1
    resources = {
      limits = {
        cpu    = "100m"
        memory = "150Mi"
      }
      requests = {
        cpu    = "100m"
        memory = "150Mi"
      }
    }
  })
  tags = {
    Purpose  = "EKS Pod Identity — workload identity"
  }
}

locals {
  service_permissions = {
    frontend = {
      actions = [
        "ecr:GetAuthorizationToken","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]
    }
    productcatalogservice = {
      actions = [
        "ecr:GetAuthorizationToken","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]
    }
    cartservice = {
      actions = [
        "elasticache:DescribeCacheClusters",
        "elasticache:DescribeReplicationGroups",
      ]
      resources = ["arn:aws:elasticache:${var.aws_region}:${var.production_account_id}:replicationgroup:cart-*"]
    }
    checkoutservice = {
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = ["arn:aws:secretsmanager:${var.aws_region}:${var.production_account_id}:secret:prod/checkout/*"]
    }
    paymentservice = {
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = ["arn:aws:secretsmanager:${var.aws_region}:${var.production_account_id}:secret:prod/payment/*"]
    }
    shippingservice = {
      actions = [
        "ecr:GetAuthorizationToken","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]
    }
    emailservice  = {
      actions = [
        "ses:SendEmail",
        "ses:SendRawEmail",
      ]
      resources = ["arn:aws:ses:${var.aws_region}:${var.production_account_id}:identity/*"]
    }
    recommendationservice = {
      actions = [
        "ecr:GetAuthorizationToken","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]
    }
    adservice = {
      actions = [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricData",
      ]
      resources = ["*"]
    }
    currencyservice = {
      actions = [
        "ecr:GetAuthorizationToken","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role" "service_roles" {
  for_each = local.service_permissions
  name = "eks-pod-${each.key}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      }
    ]
  })
  tags = {
    Service = each.key
  }
}
resource "aws_iam_role_policy" "service_role_policies" {
  for_each = local.service_permissions
  name = "${each.key}-policy"
  role = aws_iam_role.service_roles[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LeastPrivilege"
        Effect   = "Allow"
        Action   = each.value.actions
        Resource = each.value.resources
      }]
  })
}
resource "aws_eks_pod_identity_association" "services" {
  for_each = local.service_permissions
  cluster_name = var.cluster_name
  namespace = "production"
  service_account = "${each.key}-sa"
  role_arn = aws_iam_role.service_roles[each.key].arn
  tags = {
    Service = each.key
  }
  depends_on = [aws_eks_addon.pod_identity]
}

