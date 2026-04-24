# B1 TẠO OIDC
# B2 TẠO STS
# B3 TẠO ROLE
# B4 TẠO POLICY
# B5 TẠO ECR
# B6 SET CHO ECR


resource "aws_iam_role" "gha_eks_access" {
  name = "gha-eks-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDCEKSDeploy"
        Effect = "Allow"
        Principal = {
          Federated = var.github_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # SLSA L2: chỉ đúng workflow file mới được assume role
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/deploy.yml@refs/heads/main"
          }
          StringLike = {
            # Chỉ main branch
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
  max_session_duration = 1200
  tags = {
    Purpose = "GitHub Actions Access to EKS cluster"
  }
}
resource "aws_iam_role_policy" "gha_eks_access" {
  name = "ecr-push-least-privilege"
  role = aws_iam_role.gha_eks_access.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribeOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${var.production_account_id}:cluster/${var.eks_cluster_name}"
      },
      # Deny tất cả EKS destructive actions
      {
        Sid    = "DenyEKSDestructive"
        Effect = "Deny"
        Action = [
          "eks:DeleteCluster",
          "eks:CreateCluster",
          "eks:UpdateClusterConfig",
          "eks:DeleteNodegroup",
          "eks:CreateNodegroup",
          "eks:AssociateAccessPolicy",
          "eks:DisassociateAccessPolicy",
        ]
        Resource = "*"
      }
    ]
  })
}
