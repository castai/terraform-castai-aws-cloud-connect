# Terraform module for AWS Cloud Connect onboarding

This Terraform module onboards AWS accounts to [Cast AI Cloud Connect](https://cast.ai/) for cloud asset discovery. It replaces the shell-based onboarding script with a declarative, auditable, and version-controlled alternative.

## What it does

- Creates an IAM role with a trust policy allowing Cast AI to assume it
- Attaches IAM permissions based on the selected scope
- Registers the integration with the Cast AI API
- Deploys roles to member accounts via CloudFormation StackSets (org-scoped or multi-account)
- Optionally configures EKS access entries for Kubernetes object sync

## Deployment modes

### Account-scoped (default)

Runs from any AWS account. Creates the discovery role in the current account only.

```hcl
module "castai_aws_integration" {
  source = "castai/aws-cloud-connect/castai"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id
}
```

### Org-scoped

Runs from the AWS Organizations management account. The module detects this automatically and deploys discovery roles to all member accounts (or a filtered subset) via a SERVICE_MANAGED CloudFormation StackSet. Requires `organizations:DescribeOrganization` permission.

```hcl
module "castai_aws_integration" {
  source = "castai/aws-cloud-connect/castai"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id

  org_scope_enabled = true
  # Optionally limit to specific member accounts:
  # account_ids = ["111122223333", "444455556666"]
}
```

### Multi-account

Use this when you don't have management account access but want to onboard multiple accounts. The module deploys a SELF_MANAGED CloudFormation StackSet to the listed accounts.

**Prerequisites:** Each target account must have an `AWSCloudFormationStackSetExecutionRole` IAM role (or a custom role specified via `stackset_execution_role_name`) that CloudFormation can assume. The calling account must have an `AWSCloudFormationStackSetAdministrationRole` (or custom role via `stackset_administration_role_arn`). See [AWS docs](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-prereqs-self-managed.html) for setup instructions.

```hcl
module "castai_aws_integration" {
  source = "castai/aws-cloud-connect/castai"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id

  account_ids = ["111122223333", "444455556666"]

  # Optional: override default StackSet roles
  # stackset_administration_role_arn = "arn:aws:iam::MGMT_ACCOUNT:role/MyAdminRole"
  # stackset_execution_role_name     = "MyExecutionRole"
}
```

| Mode | Variable | StackSet type | Prerequisite roles |
|------|----------|---------------|--------------------|
| Account-scoped | — | None | None |
| Org-scoped | `org_scope_enabled = true` | SERVICE_MANAGED | None (AWS-managed) |
| Multi-account | `account_ids = [...]` | SELF_MANAGED | Admin role in calling account, execution role in each target account |

## Quick start

```hcl
module "castai_aws_integration" {
  source  = "castai/aws-cloud-connect/castai"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id
}
```

See [`examples/`](examples/) for more configurations.

## Scopes

| Scope | Permissions | Use case |
|-------|-------------|----------|
| `ALL` (default) | `ReadOnlyAccess` managed policy | Full cloud asset discovery |
| `AWS_COMMITMENTS` | Savings Plans + Reserved Instances | Commitment tracking |
| `AWS_AI_SERVICES` | AI/ML service read access | AI workload discovery |
| `ALL_MINIMAL_PERMISSIONS` | Subset of common services | Minimal footprint discovery |

## EKS Kubernetes object sync

To enable Kubernetes object discovery via EKS access entries:

```hcl
module "castai_aws_integration" {
  source  = "castai/aws-cloud-connect/castai"

  castai_api_key         = var.castai_api_key
  castai_organization_id = var.castai_organization_id

  eks_k8s_sync_enabled = true
  # Optionally limit to specific clusters:
  # eks_cluster_arns = ["arn:aws:eks:us-east-1:123456789012:cluster/my-cluster"]
}
```

Requires scope `ALL` or `ALL_MINIMAL_PERMISSIONS`.

- **Account-scoped:** creates EKS access entries directly via Terraform for all clusters in the current region (or the specified ARNs).
- **Org-scoped / multi-account:** deploys a Lambda via the CloudFormation StackSet that discovers and configures clusters across all regions in each member account.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.0 |
| <a name="requirement_restapi"></a> [restapi](#requirement\_restapi) | >= 1.18 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.40.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.5.0 |
| <a name="provider_restapi"></a> [restapi](#provider\_restapi) | 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudformation_stack_set.member_roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set) | resource |
| [aws_cloudformation_stack_set.multi_account_roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set) | resource |
| [aws_cloudformation_stack_set_instance.member_accounts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set_instance) | resource |
| [aws_cloudformation_stack_set_instance.multi_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set_instance) | resource |
| [aws_eks_access_entry.castai](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.castai](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_iam_policy.cur_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.org_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.castai_discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cur_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.org_management](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [restapi_object.castai_integration](https://registry.terraform.io/providers/Mastercard/restapi/latest/docs/resources/object) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_clusters.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_clusters) | data source |
| [aws_organizations_organization.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [http_http.onboarding_config](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_ids"></a> [account\_ids](#input\_account\_ids) | List of AWS account IDs to sync. For management account: filters org discovery. For non-management account: enables multi-account mode (syncs these accounts directly without Organizations API). | `list(string)` | `[]` | no |
| <a name="input_castai_api_key"></a> [castai\_api\_key](#input\_castai\_api\_key) | Cast AI API key | `string` | n/a | yes |
| <a name="input_castai_api_url"></a> [castai\_api\_url](#input\_castai\_api\_url) | Cast AI API URL | `string` | `"https://api.cast.ai"` | no |
| <a name="input_castai_organization_id"></a> [castai\_organization\_id](#input\_castai\_organization\_id) | Cast AI organization ID | `string` | n/a | yes |
| <a name="input_commitments_auto_assignment"></a> [commitments\_auto\_assignment](#input\_commitments\_auto\_assignment) | Whether to automatically assign commitments to workloads. | `bool` | `false` | no |
| <a name="input_commitments_default_status"></a> [commitments\_default\_status](#input\_commitments\_default\_status) | Default status for imported commitments (Reserved Instances, Savings Plans). One of: ACTIVE, INACTIVE. | `string` | `"INACTIVE"` | no |
| <a name="input_cur_s3_bucket_account_id"></a> [cur\_s3\_bucket\_account\_id](#input\_cur\_s3\_bucket\_account\_id) | AWS account ID that owns the CUR S3 bucket. Optional, used for cross-account bucket access. | `string` | `""` | no |
| <a name="input_cur_s3_bucket_name"></a> [cur\_s3\_bucket\_name](#input\_cur\_s3\_bucket\_name) | Name of the S3 bucket containing AWS Cost and Usage Reports (CUR). When set, grants the Cast AI role read access to the bucket. | `string` | `""` | no |
| <a name="input_cur_s3_bucket_region"></a> [cur\_s3\_bucket\_region](#input\_cur\_s3\_bucket\_region) | AWS region of the CUR S3 bucket. Required when cur\_s3\_bucket\_name is set. | `string` | `""` | no |
| <a name="input_eks_cluster_arns"></a> [eks\_cluster\_arns](#input\_eks\_cluster\_arns) | Optional list of EKS cluster ARNs to limit access entry configuration. Empty means all clusters. | `list(string)` | `[]` | no |
| <a name="input_eks_k8s_sync_enabled"></a> [eks\_k8s\_sync\_enabled](#input\_eks\_k8s\_sync\_enabled) | Enable EKS access entries for k8s object sync. Requires scope ALL or ALL\_MINIMAL\_PERMISSIONS. | `bool` | `false` | no |
| <a name="input_integration_name"></a> [integration\_name](#input\_integration\_name) | Name for the cloud asset integration | `string` | `"AWS discovery"` | no |
| <a name="input_org_scope_enabled"></a> [org\_scope\_enabled](#input\_org\_scope\_enabled) | Enable organization-scoped integration. When true, the module calls the AWS Organizations API to detect if the current account is the management account and deploys roles to member accounts via CloudFormation StackSet. Requires organizations:DescribeOrganization permission. Leave false (default) when running from a member account. | `bool` | `false` | no |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role to create | `string` | `"castai-discovery-role"` | no |
| <a name="input_scope"></a> [scope](#input\_scope) | Integration scope: ALL, AWS\_COMMITMENTS, AWS\_AI\_SERVICES, or ALL\_MINIMAL\_PERMISSIONS | `string` | `"ALL"` | no |
| <a name="input_stackset_administration_role_arn"></a> [stackset\_administration\_role\_arn](#input\_stackset\_administration\_role\_arn) | IAM role ARN for StackSet administration in multi-account mode (SELF\_MANAGED). This role must be able to assume the execution role in each target account. Defaults to AWSCloudFormationStackSetAdministrationRole in the current account. | `string` | `""` | no |
| <a name="input_stackset_execution_role_name"></a> [stackset\_execution\_role\_name](#input\_stackset\_execution\_role\_name) | Name of the IAM role in target accounts that CloudFormation StackSets will assume to deploy resources. Must exist in each target account. Defaults to AWSCloudFormationStackSetExecutionRole. | `string` | `"AWSCloudFormationStackSetExecutionRole"` | no |
| <a name="input_stackset_name"></a> [stackset\_name](#input\_stackset\_name) | Name of the CloudFormation StackSet for org-scoped deployments | `string` | `"castai-discovery-roles"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to AWS resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_castai_user_arn"></a> [castai\_user\_arn](#output\_castai\_user\_arn) | Cast AI user ARN (fetched from API) |
| <a name="output_eks_cluster_names"></a> [eks\_cluster\_names](#output\_eks\_cluster\_names) | EKS cluster names configured with Cast AI access entries (account-scoped only) |
| <a name="output_integration_id"></a> [integration\_id](#output\_integration\_id) | ID of the Cast AI cloud asset integration |
| <a name="output_is_org_scoped"></a> [is\_org\_scoped](#output\_is\_org\_scoped) | Whether this is an organization-scoped integration |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role created for Cast AI |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IAM role created for Cast AI |
| <a name="output_stackset_name"></a> [stackset\_name](#output\_stackset\_name) | Name of the CloudFormation StackSet (if org-scoped or multi-account) |
<!-- END_TF_DOCS -->