terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.37.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

#########################################################
###  AWS Organization
###  Chuẩn: NIST SP 800-207 3.3 — Multi-account isolation
#########################################################
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "sso.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
  ]
  feature_set = "ALL"
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]
}
#########################################################
###  Organization Units
#########################################################

#####################  Security  ######################
resource "aws_organizations_organizational_unit" "security" {
  name = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "log" {
  name = "Logging"
  parent_id = aws_organizations_organizational_unit.security.id
}
resource "aws_organizations_organizational_unit" "audit" {
  name = "Audit"
  parent_id = aws_organizations_organizational_unit.security.id
}

#####################  Infrastructure  ######################
resource "aws_organizations_organizational_unit" "infrastructure" {
  name = "Infrastructure"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "infra_shared" {
  name = "Shared"
  parent_id = aws_organizations_organizational_unit.infrastructure.id
}

#####################  Workloads  ######################
resource "aws_organizations_organizational_unit" "workloads" {
  name = "Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "dev" {
  name = "Devlopers"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
resource "aws_organizations_organizational_unit" "stag" {
  name = "Stagging"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
resource "aws_organizations_organizational_unit" "prod" {
  name = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

#########################################################
###  Member Accounts
#########################################################
###############   Logging account ################
resource "aws_organizations_account" "logging_account" {
  name = "Logging account"
  email = "logging@gmail.com"
  parent_id = aws_organizations_organizational_unit.log.id
  close_on_deletion = false
}
###############   Audit account ################
resource "aws_organizations_account" "audit_account" {
  name = "Audtit account"
  email = "audit@gmail.com"
  parent_id = aws_organizations_organizational_unit.audit.id
  close_on_deletion = false
}
###############   Infra account ################
resource "aws_organizations_account" "infra_shared_account" {
  name = "Infra shared account"
  email = "infra@gmail.com"
  parent_id = aws_organizations_organizational_unit.infra_shared.id
  close_on_deletion = false
}
###############   Dev account ################
resource "aws_organizations_account" "dev_account" {
  name = "Dev account"
  email = "dev@gmail.com"
  parent_id = aws_organizations_organizational_unit.dev.id
  close_on_deletion = false
}
###############   Staging account ################
resource "aws_organizations_account" "staging_account" {
  name = "Stagging account"
  email = "staging@gmail.com"
  parent_id = aws_organizations_organizational_unit.stag.id
  close_on_deletion = false
}
###############   Production account ################
resource "aws_organizations_account" "production_account" {
  name = "Production account"
  email = "production@gmail.com"
  parent_id = aws_organizations_organizational_unit.prod.id
  close_on_deletion = false
}

#########################################################
###  Service Control Policies (SCP)
###  Chuẩn: NIST 800-207 Tenet 3 — Least privilege
#########################################################
# SCP 1: Deny tất cả actions ngoài ap-southeast-1
# Prevent data exfiltration sang region khác
resource "aws_organizations_policy" "deny_non_approved_regions" {
  name        = "DenyNonApprovedRegions"
  description = "NIST 800-207: Restrict resource creation to approved regions only"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonApprovedRegions"
        Effect = "Deny"
        NotAction = [
          # Các service global — không restrict region
          "iam:*",
          "organizations:*",
          "route53:*",
          "budgets:*",
          "support:*",
          "sts:AssumeRole",
          "cloudfront:*",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = "ap-southeast-1"
          }
        }
      }
    ]
  })
}

# SCP 2: Deny tạo IAM User (phải dùng IAM Identity Center)
# Chuẩn: NIST 800-207 — No long-lived credentials
resource "aws_organizations_policy" "deny_iam_user_creation" {
  name        = "DenyIAMUserCreation"
  description = "NIST 800-207 Tenet 6: Force use of IAM Identity Center, no IAM Users"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMUserCreation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey", 
        ]
        Resource = "*"
      }
    ]
  })
}

# SCP 3: Deny disable CloudTrail
# Chuẩn: NIST 800-207 Tenet 7 — Always monitor
resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  name        = "DenyDisableCloudTrail"
  description = "NIST 800-207 Tenet 7: Audit logs must always be enabled"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisableCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
        ]
        Resource = "*"
      }
    ]
  })
}

# SCP 4: Production — Deny mọi thứ nếu không có MFA
# Chuẩn: NIST 800-207 Tenet 6 — MFA required
resource "aws_organizations_policy" "require_mfa_production" {
  name        = "RequireMFAProduction"
  description = "NIST 800-207 Tenet 6: MFA required for all production actions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyWithoutMFA"
        Effect = "Deny"
        NotAction = [
          "sts:GetSessionToken", 
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
}
###################   Attach policy to OU   #####################
resource "aws_organizations_policy_attachment" "deny_region" {
  policy_id = aws_organizations_policy.deny_non_approved_regions.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
resource "aws_organizations_policy_attachment" "deny_create_user" {
  policy_id = aws_organizations_policy.deny_iam_user_creation.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "deny_disable_cloudtrail" {
  policy_id = aws_organizations_policy.deny_disable_cloudtrail.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "require_mfa_production" {
  policy_id = aws_organizations_policy.require_mfa_production.id
  target_id = aws_organizations_organizational_unit.prod.id
}