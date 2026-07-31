provider "restapi" {
  uri                  = var.castai_api_url
  write_returns_object = true

  headers = {
    "Content-Type" = "application/json"
    "X-API-Key"    = var.castai_api_key
  }
}

locals {
  integration_metadata = merge(
    {
      crossRoleUserArn  = local.castai_user_arn
      organizationScope = local.is_management_account || local.is_multi_account
    },
    (local.is_management_account || local.is_multi_account) && length(var.account_ids) > 0 ? {
      accountIds = var.account_ids
    } : {},
    local.eks_enabled ? {
      k8sObjectsSyncEnabled = true
    } : {},
    local.eks_enabled && length(var.eks_cluster_arns) > 0 ? {
      eksClusterArns = var.eks_cluster_arns
    } : {},
    var.cur_s3_bucket_name != "" ? {
      curS3Bucket = merge(
        {
          name   = var.cur_s3_bucket_name
          region = var.cur_s3_bucket_region
        },
        var.cur_s3_bucket_account_id != "" ? { accountId = var.cur_s3_bucket_account_id } : {}
      )
    } : {}
  )
}

resource "restapi_object" "castai_integration" {
  path = "/inventory/v1beta/organizations/${var.castai_organization_id}/cloud-asset-integrations"

  update_method = "PATCH"

  data = jsonencode({
    enabled  = true
    name     = var.integration_name
    provider = "AWS"
    scope    = var.scope
    aws_credentials = {
      assume_role_arn = aws_iam_role.castai_discovery.arn
    }
    metadata = local.integration_metadata
    settings = {
      commitments = {
        defaultStatus  = var.commitments_default_status
        autoAssignment = var.commitments_auto_assignment
      }
    }
  })

  depends_on = [
    aws_iam_role_policy_attachment.org_management,
    aws_iam_role_policy_attachment.discovery,
    aws_iam_role_policy_attachment.managed,
    aws_cloudformation_stack_set_instance.member_accounts,
    aws_cloudformation_stack_set_instance.multi_account,
    aws_eks_access_policy_association.castai,
  ]

  # GET returns a different shape than we POST, so the provider rewrites `data`
  # on every refresh, producing a permanent diff that no apply can resolve.
  lifecycle {
    ignore_changes = [data]
  }
}
