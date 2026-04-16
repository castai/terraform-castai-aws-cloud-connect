provider "aws" {
  region = "us-east-1"
}

module "castai_aws_integration" {
  source = "../../"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id

  scope            = "ALL"
  integration_name = "AWS Discovery via Terraform"

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "Cast AI Cloud Asset Discovery"
  }

  eks_k8s_sync_enabled = true
}

variable "castai_api_key" {
  type      = string
  sensitive = true
}

variable "castai_organization_id" {
  type = string
}

output "role_arn" {
  value = module.castai_aws_integration.role_arn
}

output "integration_id" {
  value = module.castai_aws_integration.integration_id
}

output "is_org_scoped" {
  value = module.castai_aws_integration.is_org_scoped
}
