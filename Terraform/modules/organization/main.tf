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
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "log" {
  name      = "Logging"
  parent_id = aws_organizations_organizational_unit.security.id
}
resource "aws_organizations_organizational_unit" "audit" {
  name      = "Audit"
  parent_id = aws_organizations_organizational_unit.security.id
}
resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "infra_shared" {
  name      = "Shared"
  parent_id = aws_organizations_organizational_unit.infrastructure.id
}
resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.main.roots[0].id
}
resource "aws_organizations_organizational_unit" "dev" {
  name      = "Devlopers"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
resource "aws_organizations_organizational_unit" "stag" {
  name      = "Stagging"
  parent_id = aws_organizations_organizational_unit.workloads.id
}
resource "aws_organizations_organizational_unit" "prod" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

# Member accounts commented out — waiting for quota increase
# Uncomment when AWS approves limit increase to 10
# resource "aws_organizations_account" "logging_account" { ... }
# resource "aws_organizations_account" "audit_account" { ... }
# resource "aws_organizations_account" "infra_shared_account" { ... }
# resource "aws_organizations_account" "dev_account" { ... }
# resource "aws_organizations_account" "staging_account" { ... }
# resource "aws_organizations_account" "production_account" { ... }

#########################################################
###  Service Control Policies
#########################################################
resource "aws_organizations_policy" "deny_non_approved_regions" {
  name        = "DenyNonApprovedRegions"
  description = "NIST 800-207: Restrict resource creation to approved regions only"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyNonApprovedRegions"
      Effect = "Deny"
      NotAction = [
        "iam:*", "organizations:*", "route53:*",
        "budgets:*", "support:*", "sts:AssumeRole", "cloudfront:*",
      ]
      Resource  = "*"
      Condition = { StringNotEquals = { "aws:RequestedRegion" = "ap-southeast-1" } }
    }]
  })
}

resource "aws_organizations_policy" "deny_iam_user_creation" {
  name        = "DenyIAMUserCreation"
  description = "NIST 800-207 Tenet 6: Force use of IAM Identity Center"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyIAMUserCreation"
      Effect   = "Deny"
      Action   = ["iam:CreateUser", "iam:CreateAccessKey"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  name        = "DenyDisableCloudTrail"
  description = "NIST 800-207 Tenet 7: Audit logs must always be enabled"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyDisableCloudTrail"
      Effect   = "Deny"
      Action   = ["cloudtrail:DeleteTrail", "cloudtrail:StopLogging", "cloudtrail:UpdateTrail"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy" "require_mfa_production" {
  name        = "RequireMFAProduction"
  description = "NIST 800-207 Tenet 6: MFA required for all production actions"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyWithoutMFA"
      Effect    = "Deny"
      NotAction = ["sts:GetSessionToken"]
      Resource  = "*"
      Condition = { BoolIfExists = { "aws:MultiFactorAuthPresent" = "false" } }
    }]
  })
}

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
