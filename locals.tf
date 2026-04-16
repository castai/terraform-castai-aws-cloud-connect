locals {
  current_account_id = data.aws_caller_identity.current.account_id

  # Determine if this is a management account (org-scoped)
  is_management_account = var.org_scope_enabled ? (
    try(data.aws_organizations_organization.current[0].master_account_id == local.current_account_id, false)
  ) : false

  # Multi-account mode: not a management account, but explicit account IDs provided.
  # Syncs multiple accounts without needing management account access or Organizations APIs.
  is_multi_account = !local.is_management_account && length(var.account_ids) > 0

  # Permissions and managed policies are fetched from the API
  selected_permissions      = local.api_permissions
  selected_managed_policies = local.api_managed_policies

  # Filter account IDs for stackset (exclude current account — role is created directly via iam.tf)
  stackset_account_ids = [for id in var.account_ids : id if id != local.current_account_id]

  # Whether the current account is in the explicit account list (multi-account mode)
  current_account_in_list = local.is_multi_account && contains(var.account_ids, local.current_account_id)

  # Admin role ARN for SELF_MANAGED StackSets (multi-account mode)
  stackset_admin_role_arn = var.stackset_administration_role_arn != "" ? var.stackset_administration_role_arn : "arn:aws:iam::${local.current_account_id}:role/AWSCloudFormationStackSetAdministrationRole"

  # Determine if management account should have discovery permissions
  attach_discovery_to_management = local.is_management_account && (
    length(var.account_ids) == 0 || contains(var.account_ids, local.current_account_id)
  )

  # EKS access entry configuration — see eks.tf
  eks_cluster_arns_csv = join(",", var.eks_cluster_arns)

  # CUR S3 bucket read statement — appended to the discovery policy when a bucket is configured
  cur_s3_statement = var.cur_s3_bucket_name != "" ? [
    {
      Effect = "Allow"
      Action = ["s3:Get*", "s3:List*"]
      Resource = [
        "arn:aws:s3:::${var.cur_s3_bucket_name}",
        "arn:aws:s3:::${var.cur_s3_bucket_name}/*",
      ]
    }
  ] : []
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_organizations_organization" "current" {
  count = var.org_scope_enabled ? 1 : 0
}
