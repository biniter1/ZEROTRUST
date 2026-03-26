# B1 TẠO OIDC
# B2 TẠO STS
# B3 TẠO ROLE
# B4 TẠO POLICY
# B5 TẠO ECR
# B6 SET CHO ECR

# Tạo OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
  tags = {
    Purpose  = "GitHub Actions OIDC federation"
    Standard = "NIST-800-207-Tenet6"
  }
}
resource "aws_iam_role" "gha_ecr_push" {
  name = "gha-ecr-push-role"
  assume_role_policy = code({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDCECRPush"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # SLSA L2: chỉ đúng workflow file mới được assume role
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/build.yml@refs/heads/main"
          }
          StringLike = {
            # Chỉ main branch
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
  max_session_duration = 900
  tags = {
    Purpose = "GitHub Actions ECR push"
  }
}
resource "aws_iam_role_policy" "gha_ecr_push" {
  name = "ecr-push-least-privilege"
  role = aws_iam_role.gha_ecr_push.id
  policy = jsondecode({
    Version = "2012-10-17"
    Statement = [
    # ECR auth token — required cho mọi ECR operation
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      # ECR push — chỉ repository của project
      {
        Sid    = "ECRPushSpecificRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          # Cosign cần để lưu signature
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
        ]
        # Scoped: chỉ online-boutique repo, không phải tất cả
        Resource = "arn:aws:ecr:${var.aws_region}:${var.production_account_id}:repository/online-boutique/*"
      },
      # Deny tất cả ECR admin operations
      {
        Sid    = "DenyECRAdmin"
        Effect = "Deny"
        Action = [
          "ecr:DeleteRepository",
          "ecr:DeleteRepositoryPolicy",
          "ecr:CreateRepository",
        ]
        Resource = "*"
      }
    ]
  })
}
data "aws_caller_identity" "current" {}
resource "aws_kms_key" "key-ecr" {
  description = "KMS ket for ECR encryption"
  enable_key_rotation = true
  deletion_window_in_days = 20
  
  tags = {
    Purpose = "Key for ECR Encryption"
  }
}
resource "aws_ecr_repository" "services" {
  for_each = toset([
    "frontend",
    "productcatalogservice",
    "cartservice",
    "checkoutservice",
    "paymentservice",
    "shippingservice",
    "emailservice",
    "recommendationservice",
    "adservice",
    "currencyservice",
  ])
  name = "online-boutique/${each.key}"
  image_tag_mutability = "IMMUTABLE" 
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.key-ecr.arn
  }
  tags = {
    Service  = each.key
  }
}
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}