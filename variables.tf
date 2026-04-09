variable "castai_api_url" {
  description = "CAST AI API URL"
  type        = string
  default     = "https://api.cast.ai"
}

variable "castai_api_key" {
  description = "CAST AI API key"
  type        = string
  sensitive   = true
}

variable "castai_organization_id" {
  description = "CAST AI organization ID"
  type        = string
}

variable "integration_name" {
  description = "Name for the cloud asset integration"
  type        = string
  default     = "AWS discovery"
}

variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
  default     = "castai-discovery-role"
}

variable "scope" {
  description = "Integration scope: ALL, AWS_COMMITMENTS, AWS_AI_SERVICES, or ALL_MINIMAL_PERMISSIONS"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "AWS_COMMITMENTS", "AWS_AI_SERVICES", "ALL_MINIMAL_PERMISSIONS"], var.scope)
    error_message = "Scope must be one of: ALL, AWS_COMMITMENTS, AWS_AI_SERVICES, ALL_MINIMAL_PERMISSIONS"
  }
}

variable "force_account_scope" {
  description = "Force account-scoped integration even if running in a management account"
  type        = bool
  default     = false
}

variable "account_ids" {
  description = "List of AWS account IDs to sync. For management account: filters org discovery. For non-management account: enables multi-account mode (syncs these accounts directly without Organizations API)."
  type        = list(string)
  default     = []
}

variable "stackset_name" {
  description = "Name of the CloudFormation StackSet for org-scoped deployments"
  type        = string
  default     = "castai-discovery-roles"
}

variable "eks_k8s_sync_enabled" {
  description = "Enable EKS access entries for k8s object sync. Requires scope ALL or ALL_MINIMAL_PERMISSIONS."
  type        = bool
  default     = false
}

variable "eks_cluster_arns" {
  description = "Optional list of EKS cluster ARNs to limit access entry configuration. Empty means all clusters."
  type        = list(string)
  default     = []
}

variable "stackset_administration_role_arn" {
  description = "IAM role ARN for StackSet administration in multi-account mode (SELF_MANAGED). This role must be able to assume the execution role in each target account. Defaults to AWSCloudFormationStackSetAdministrationRole in the current account."
  type        = string
  default     = ""
}

variable "stackset_execution_role_name" {
  description = "Name of the IAM role in target accounts that CloudFormation StackSets will assume to deploy resources. Must exist in each target account. Defaults to AWSCloudFormationStackSetExecutionRole."
  type        = string
  default     = "AWSCloudFormationStackSetExecutionRole"
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
