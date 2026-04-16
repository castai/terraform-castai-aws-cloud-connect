# CloudFormation StackSet template and parameter overrides shared by both
# SERVICE_MANAGED (org-scoped) and SELF_MANAGED (multi-account) StackSets.

locals {
  stackset_template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Cast AI discovery role for member accounts - ${var.scope} scope"

    Parameters = merge(
      {
        CastUserArn = {
          Type        = "String"
          Description = "Cast AI user ARN"
        }
        OrganizationId = {
          Type        = "String"
          Description = "Cast AI organization ID"
        }
        RoleName = {
          Type        = "String"
          Description = "IAM role name for discovery"
        }
      },
      local.eks_enabled ? {
        AllowedClusterArns = {
          Type        = "String"
          Description = "Comma-separated list of EKS cluster ARNs to configure access for (empty means all)"
          Default     = ""
        }
      } : {}
    )

    Resources = merge(
      {
        CastDiscoveryRole = {
          Type = "AWS::IAM::Role"
          Properties = {
            RoleName = { Ref = "RoleName" }
            AssumeRolePolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect = "Allow"
                  Principal = {
                    AWS = { Ref = "CastUserArn" }
                  }
                  Action = "sts:AssumeRole"
                  Condition = {
                    StringEquals = {
                      "sts:ExternalId" = { Ref = "OrganizationId" }
                    }
                  }
                }
              ]
            }
            ManagedPolicyArns = local.selected_managed_policies
          }
        }
      },
      length(local.selected_permissions) > 0 ? {
        PermissionsPolicy = {
          Type = "AWS::IAM::Policy"
          Properties = {
            PolicyName = "castai-${lower(replace(var.scope, "_", "-"))}-readonly-policy"
            Roles      = [{ Ref = "CastDiscoveryRole" }]
            PolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect   = "Allow"
                  Action   = local.selected_permissions
                  Resource = "*"
                }
              ]
            }
          }
        }
      } : {},
      jsondecode(local.eks_cfn_resources_stackset)
    )

    Outputs = {
      RoleArn = {
        Description = "ARN of the created role"
        Value       = { "Fn::GetAtt" = ["CastDiscoveryRole", "Arn"] }
      }
    }
  })

  stackset_parameter_overrides = merge(
    {
      CastUserArn    = local.castai_user_arn
      OrganizationId = var.castai_organization_id
      RoleName       = var.role_name
    },
    local.eks_enabled ? {
      AllowedClusterArns = local.eks_cluster_arns_csv
    } : {}
  )
}

# =============================================================================
# SERVICE_MANAGED StackSet — org-scoped via management account
# =============================================================================

resource "aws_cloudformation_stack_set" "member_roles" {
  count = local.is_management_account ? 1 : 0

  name             = var.stackset_name
  description      = "Cast AI discovery role for member accounts - ${var.scope} scope"
  permission_model = "SERVICE_MANAGED"
  tags             = var.tags

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  capabilities  = ["CAPABILITY_NAMED_IAM"]
  template_body = local.stackset_template_body

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "member_accounts" {
  count = local.is_management_account ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.member_roles[0].name
  stack_set_instance_region = "us-east-1"

  deployment_targets {
    organizational_unit_ids = [data.aws_organizations_organization.current[0].roots[0].id]
    account_filter_type     = length(var.account_ids) > 0 ? "INTERSECTION" : null
    accounts                = length(var.account_ids) > 0 ? local.stackset_account_ids : null
  }

  parameter_overrides = local.stackset_parameter_overrides

  operation_preferences {
    max_concurrent_percentage = 100
  }
}

# =============================================================================
# SELF_MANAGED StackSet — multi-account mode without management account
# =============================================================================
# Prerequisites:
# - AWSCloudFormationStackSetAdministrationRole (or custom) in the calling account
# - AWSCloudFormationStackSetExecutionRole (or custom) in each target account
# See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-prereqs-self-managed.html

resource "aws_cloudformation_stack_set" "multi_account_roles" {
  count = local.is_multi_account && length(local.stackset_account_ids) > 0 ? 1 : 0

  name             = var.stackset_name
  description      = "Cast AI discovery role for target accounts - ${var.scope} scope"
  permission_model = "SELF_MANAGED"
  tags             = var.tags

  administration_role_arn = local.stackset_admin_role_arn
  execution_role_name     = var.stackset_execution_role_name

  capabilities  = ["CAPABILITY_NAMED_IAM"]
  template_body = local.stackset_template_body
}

resource "aws_cloudformation_stack_set_instance" "multi_account" {
  count = local.is_multi_account && length(local.stackset_account_ids) > 0 ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.multi_account_roles[0].name
  stack_set_instance_region = data.aws_region.current.id

  # Deploy to each target account (excluding the current account)
  deployment_targets {
    accounts = local.stackset_account_ids
  }

  parameter_overrides = local.stackset_parameter_overrides

  operation_preferences {
    max_concurrent_percentage = 100
  }
}
