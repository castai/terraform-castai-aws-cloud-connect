output "role_arn" {
  description = "ARN of the IAM role created for CAST AI"
  value       = aws_iam_role.castai_discovery.arn
}

output "castai_user_arn" {
  description = "CAST AI user ARN (fetched from API)"
  value       = local.castai_user_arn
}

output "role_name" {
  description = "Name of the IAM role created for CAST AI"
  value       = aws_iam_role.castai_discovery.name
}

output "integration_id" {
  description = "ID of the CAST AI cloud asset integration"
  value       = jsondecode(restapi_object.castai_integration.api_response).id
}

output "is_org_scoped" {
  description = "Whether this is an organization-scoped integration"
  value       = local.is_management_account || local.is_multi_account
}

output "stackset_name" {
  description = "Name of the CloudFormation StackSet (if org-scoped or multi-account)"
  value = (
    local.is_management_account ? aws_cloudformation_stack_set.member_roles[0].name :
    local.is_multi_account && length(local.stackset_account_ids) > 0 ? aws_cloudformation_stack_set.multi_account_roles[0].name :
    null
  )
}

output "eks_cluster_names" {
  description = "EKS cluster names configured with CAST AI access entries (account-scoped only)"
  value       = local.eks_cluster_names
}
