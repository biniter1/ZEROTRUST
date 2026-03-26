# ============================================================
# IAM IDENTITY CENTER (SSO)
# Chuẩn: NIST SP 800-207 §2.1 — Centralized Identity
# CISA ZTMM Identity Pillar — Single source of truth
# ============================================================

data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn      = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  sso_identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

#########################################################
###  Groups
#########################################################
resource "aws_identitystore_group" "log" {
  display_name = "SOCs"
  identity_store_id = local.sso_identity_store_id
}
resource "aws_identitystore_group" "audit" {
  display_name = "Audits"
  identity_store_id = local.sso_identity_store_id
}
resource "aws_identitystore_group" "infra" {
  display_name = "Infrastructure"
  identity_store_id = local.sso_identity_store_id
}
resource "aws_identitystore_group" "developer" {
  display_name = "Developers"
  identity_store_id = local.sso_identity_store_id
}
resource "aws_identitystore_group" "devops" {
  display_name = "DevOps"
  identity_store_id = local.sso_identity_store_id
}
resource "aws_identitystore_group" "admin" {
  display_name = "Admins"
  identity_store_id = local.sso_identity_store_id
}

#########################################################
###  User
#########################################################
resource "aws_identitystore_user" "developer_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "Developer 01"
  user_name         = "developer-01"

  name {
    given_name  = "Developer"
    family_name = "01"
  }

  emails {
    value   = "developer01@gmail.com"
    type    = "work"
    primary = true
  }
}
resource "aws_identitystore_user" "devops_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "Devops 01"
  user_name         = "devops-01"

  name {
    given_name  = "Devops"
    family_name = "01"
  }

  emails {
    value   = "devops01@gmail.com"
    type    = "work"
    primary = true
  }
}
resource "aws_identitystore_user" "admin_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "Admin 01"
  user_name         = "admin-01"

  name {
    given_name  = "Admin"
    family_name = "01"
  }

  emails {
    value   = "admin01@gmail.com"
    type    = "work"
    primary = true
  }
}
resource "aws_identitystore_user" "soc_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "SOC 01"
  user_name         = "soc-01"

  name {
    given_name  = "SOC"
    family_name = "01"
  }

  emails {
    value   = "soc01@gmail.com"
    type    = "work"
    primary = true
  }
}
resource "aws_identitystore_user" "audit_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "Auditer 01"
  user_name         = "auditer-01"

  name {
    given_name  = "Audit"
    family_name = "01"
  }

  emails {
    value   = "auditer01@gmail.com"
    type    = "work"
    primary = true
  }
}
resource "aws_identitystore_user" "infra_01" {
  identity_store_id = local.sso_identity_store_id
  display_name      = "Infrastructure 01"
  user_name         = "infrastructure-01"

  name {
    given_name  = "Infra"
    family_name = "01"
  }

  emails {
    value   = "infrastructure01@gmail.com"
    type    = "work"
    primary = true
  }
}
###################   Gán User vào Group   #######################
resource "aws_identitystore_group_membership" "developer_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.developer.group_id
  member_id         = aws_identitystore_user.developer_01.user_id
}
resource "aws_identitystore_group_membership" "devops_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.devops.group_id
  member_id         = aws_identitystore_user.devops_01.user_id
}
resource "aws_identitystore_group_membership" "admin_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.admin.group_id
  member_id         = aws_identitystore_user.admin_01.user_id
}
resource "aws_identitystore_group_membership" "soc_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.soc.group_id
  member_id         = aws_identitystore_user.soc_01.user_id
}
resource "aws_identitystore_group_membership" "audit_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.audit.group_id
  member_id         = aws_identitystore_user.audit_01.user_id
}
resource "aws_identitystore_group_membership" "infra_01" {
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.infra.group_id
  member_id         = aws_identitystore_user.infra_01.user_id
}

#########################################################
###  PERMISSION SETS — Quyền cho từng role
###  Chuẩn: NIST 800-207 Tenet 3 — Least Privilege
#########################################################
# ============================================================
# PERMISSION SET 1: Developer
# Chuẩn: NIST 800-207 Tenet 3 — Least Privilege
# Scope: Dev only, ECR pull, CloudWatch logs dev
# ============================================================

resource "aws_ssoadmin_permission_set" "developer" {
  name             = "DeveloperAccess"
  description      = "NIST 800-207 T3: Dev env only, ECR pull, logs read"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"

  tags = {
    Role     = "developer"
    Standard = "NIST-800-207-Tenet3"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "developer" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR — pull image only
      {
        Sid    = "ECRPullOnly"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
        ]
        Resource = "*"
      },
      # CloudWatch Logs — chỉ log group dev
      {
        Sid    = "CloudWatchLogsDevOnly"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:FilterLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:log-group:/dev/*"
      },
      # EKS — describe cluster dev để lấy kubeconfig
      {
        Sid    = "EKSDevDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "arn:aws:eks:*:*:cluster/*dev*"
      },
      # Deny tất cả staging/prod resources
      {
        Sid    = "DenyStagingProdAccess"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = ["staging", "production"]
          }
        }
      }
    ]
  })
}

# Account assignment — Dev account only
resource "aws_ssoadmin_account_assignment" "developer_dev" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
  principal_id       = aws_identitystore_group.developer.group_id
  principal_type     = "GROUP"
  target_id          = var.dev_account_id
  target_type        = "AWS_ACCOUNT"
}

# ============================================================
# PERMISSION SET 2: DevOps
# Chuẩn: NIST 800-207 Tenet 3 — Least Privilege
# Scope: Full dev+staging, ECR push/pull, prod read-only
# ============================================================

resource "aws_ssoadmin_permission_set" "devops" {
  name             = "DevOpsAccess"
  description      = "NIST 800-207 T3: Full dev/staging, ECR push, prod read-only"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role     = "devops"
    Standard = "NIST-800-207-Tenet3"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "devops" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR — push và pull (dev + staging)
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:TagResource",
        ]
        Resource = "*"
      },
      # CloudWatch Logs — dev + staging
      {
        Sid    = "CloudWatchLogsDevStaging"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/dev/*",
          "arn:aws:logs:*:*:log-group:/staging/*",
        ]
      },
      # EKS — full dev/staging
      {
        Sid    = "EKSDevStagingFull"
        Effect = "Allow"
        Action = ["eks:*"]
        Resource = [
          "arn:aws:eks:*:*:cluster/*dev*",
          "arn:aws:eks:*:*:cluster/*staging*",
        ]
      },
      # Production — read-only
      {
        Sid    = "ProductionReadOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:ListAddons",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = "production"
          }
        }
      },
      # Deny destructive actions trên production
      {
        Sid    = "DenyProductionDestructive"
        Effect = "Deny"
        Action = [
          "eks:DeleteCluster",
          "eks:DeleteNodegroup",
          "ec2:TerminateInstances",
          "rds:DeleteDBInstance",
          "iam:DeleteRole",
          "iam:DetachRolePolicy",
          "iam:CreateAccessKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = "production"
          }
        }
      }
    ]
  })
}

# Account assignment — Dev + Staging full, Prod read-only
resource "aws_ssoadmin_account_assignment" "devops_dev" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn
  principal_id       = aws_identitystore_group.devops.group_id
  principal_type     = "GROUP"
  target_id          = var.dev_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "devops_staging" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn
  principal_id       = aws_identitystore_group.devops.group_id
  principal_type     = "GROUP"
  target_id          = var.staging_account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "devops_prod_readonly" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn # Reuse read-only
  principal_id       = aws_identitystore_group.devops.group_id
  principal_type     = "GROUP"
  target_id          = var.production_account_id
  target_type        = "AWS_ACCOUNT"
}

# ============================================================
# PERMISSION SET 3: Admin
# Chuẩn: NIST 800-207 Tenet 6 — MFA required
# Scope: Full access, giới hạn bởi SCP ở Organizations level
# ============================================================

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "AdminAccess"
  description      = "NIST 800-207 T6: Full access, MFA enforced by SCP, 1h session"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT1H" # Short session — bắt buộc

  tags = {
    Role     = "admin"
    Standard = "NIST-800-207-Tenet6"
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "admin_full" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  # Bị giới hạn bởi 4 SCPs ở Organizations:
  # 1. DenyNonApprovedRegions
  # 2. DenyIAMUserCreation
  # 3. DenyDisableCloudTrail
  # 4. RequireMFAProduction (prod account)
}

# Assign tất cả accounts
resource "aws_ssoadmin_account_assignment" "admin_dev" {
  for_each = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
    prod    = var.production_account_id
  }
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = aws_identitystore_group.admin.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

# ============================================================
# PERMISSION SET 4: SOC (Security Operations Center)
# Chuẩn: NIST 800-207 Tenet 7 — Monitor & detect
# Scope: CloudTrail + GuardDuty + Security Hub — cả 3 môi trường
# ============================================================

resource "aws_ssoadmin_permission_set" "soc" {
  name             = "SOCAccess"
  description      = "NIST 800-207 T7: Security monitoring - CloudTrail, GuardDuty, Security Hub"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role     = "soc"
    Standard = "NIST-800-207-Tenet7"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "soc" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.soc.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudTrail — read logs cả 3 môi trường
      {
        Sid    = "CloudTrailReadAll"
        Effect = "Allow"
        Action = [
          "cloudtrail:GetTrail",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
          "cloudtrail:LookupEvents",
          "cloudtrail:ListTrails",
          "cloudtrail:GetEventSelectors",
        ]
        Resource = "*"
      },
      # GuardDuty — view findings
      {
        Sid    = "GuardDutyReadAll"
        Effect = "Allow"
        Action = [
          "guardduty:GetDetector",
          "guardduty:GetFindings",
          "guardduty:ListFindings",
          "guardduty:ListDetectors",
          "guardduty:GetFindingsStatistics",
          "guardduty:DescribeOrganizationConfiguration",
        ]
        Resource = "*"
      },
      # Security Hub — view findings + compliance
      {
        Sid    = "SecurityHubReadAll"
        Effect = "Allow"
        Action = [
          "securityhub:GetFindings",
          "securityhub:ListFindingAggregators",
          "securityhub:GetInsights",
          "securityhub:GetInsightResults",
          "securityhub:DescribeHub",
          "securityhub:GetEnabledStandards",
          "securityhub:DescribeStandards",
          "securityhub:DescribeStandardsControls",
        ]
        Resource = "*"
      },
      # CloudWatch Logs — security-related log groups
      {
        Sid    = "CloudWatchSecurityLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:StartQuery",
          "logs:GetQueryResults",
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/eks/*/cluster",
          "arn:aws:logs:*:*:log-group:/aws/cloudtrail/*",
          "arn:aws:logs:*:*:log-group:/aws/guardduty/*",
        ]
      },
      # Deny mọi write action
      {
        Sid    = "DenyAllWrite"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DeleteFilter",
          "securityhub:DeleteHub",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
        ]
        Resource = "*"
      }
    ]
  })
}

# SOC access tất cả 3 accounts để monitor
resource "aws_ssoadmin_account_assignment" "soc_all" {
  for_each = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
    prod    = var.production_account_id
  }
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.soc.arn
  principal_id       = aws_identitystore_group.soc.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

# ============================================================
# PERMISSION SET 5: Audit
# Chuẩn: NIST 800-207 Tenet 7 + Compliance
# Scope: CloudTrail, Config, Billing, Compliance reports
# ============================================================

resource "aws_ssoadmin_permission_set" "audit" {
  name             = "AuditAccess"
  description      = "Compliance: CloudTrail, Config, Billing, Compliance reports - read only"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"

  tags = {
    Role     = "audit"
    Standard = "NIST-800-207-Tenet7"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "audit" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.audit.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudTrail — audit logs
      {
        Sid    = "CloudTrailAudit"
        Effect = "Allow"
        Action = [
          "cloudtrail:LookupEvents",
          "cloudtrail:GetTrail",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:ListTrails",
        ]
        Resource = "*"
      },
      # AWS Config — compliance reports
      {
        Sid    = "ConfigReadOnly"
        Effect = "Allow"
        Action = [
          "config:GetComplianceDetailsByConfigRule",
          "config:GetComplianceDetailsByResource",
          "config:GetComplianceSummaryByConfigRule",
          "config:GetComplianceSummaryByResourceType",
          "config:DescribeConfigRules",
          "config:DescribeConfigRuleEvaluationStatus",
          "config:GetResourceConfigHistory",
          "config:ListDiscoveredResources",
        ]
        Resource = "*"
      },
      # Billing — cost và usage reports
      {
        Sid    = "BillingReadOnly"
        Effect = "Allow"
        Action = [
          "aws-portal:ViewBilling",
          "aws-portal:ViewUsage",
          "budgets:ViewBudget",
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetUsageForecast",
          "cur:DescribeReportDefinitions",
        ]
        Resource = "*"
      },
      # Security Hub — compliance reports
      {
        Sid    = "SecurityHubCompliance"
        Effect = "Allow"
        Action = [
          "securityhub:GetEnabledStandards",
          "securityhub:DescribeStandards",
          "securityhub:DescribeStandardsControls",
          "securityhub:GetFindings",
        ]
        Resource = "*"
      },
      # Deny tất cả write
      {
        Sid      = "DenyAllWrite"
        Effect   = "Deny"
        NotAction = [
          "cloudtrail:LookupEvents",
          "config:Get*",
          "config:Describe*",
          "config:List*",
          "ce:Get*",
          "budgets:View*",
          "securityhub:Get*",
          "securityhub:Describe*",
          "aws-portal:View*",
          "cur:Describe*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssoadmin_account_assignment" "audit_all" {
  for_each = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
    prod    = var.production_account_id
  }
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.audit.arn
  principal_id       = aws_identitystore_group.audit.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

# ============================================================
# PERMISSION SET 6: Infrastructure
# Chuẩn: NIST 800-207 Tenet 3 — Least Privilege
# Scope: VPC, EKS, networking resources — read-only cả 3 môi trường
# ============================================================

resource "aws_ssoadmin_permission_set" "infrastructure" {
  name             = "InfrastructureAccess"
  description      = "NIST 800-207 T3: Infrastructure read-only - VPC, EKS, networking"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Role     = "infrastructure"
    Standard = "NIST-800-207-Tenet3"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "infrastructure" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.infrastructure.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # VPC + Networking — read only
      {
        Sid    = "VPCReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
        ]
        Resource = "*"
      },
      # EKS — read only cả 3 môi trường
      {
        Sid    = "EKSReadOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup",
          "eks:ListAddons",
          "eks:DescribeAddon",
          "eks:ListFargateProfiles",
        ]
        Resource = "*"
      },
      # Load Balancer — read only
      {
        Sid    = "ELBReadOnly"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
        ]
        Resource = "*"
      },
      # Route53 + DNS — read only
      {
        Sid    = "Route53ReadOnly"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      },
      # CloudWatch metrics cho infra
      {
        Sid    = "CloudWatchMetricsReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
        ]
        Resource = "*"
      },
      # Deny tất cả write/delete
      {
        Sid    = "DenyAllWrite"
        Effect = "Deny"
        Action = [
          "ec2:Create*",
          "ec2:Delete*",
          "ec2:Modify*",
          "ec2:Terminate*",
          "eks:Create*",
          "eks:Delete*",
          "eks:Update*",
          "elasticloadbalancing:Create*",
          "elasticloadbalancing:Delete*",
          "route53:Change*",
          "route53:Create*",
          "route53:Delete*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssoadmin_account_assignment" "infrastructure_all" {
  for_each = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
    prod    = var.production_account_id
  }
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.infrastructure.arn
  principal_id       = aws_identitystore_group.infrastructure.group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}