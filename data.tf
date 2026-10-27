# Fetch structured onboarding config from the Cast AI API
data "http" "onboarding_config" {
  url = "${var.castai_api_url}/inventory/v1beta/organizations/${var.castai_organization_id}/cloud-asset-integrations:getOnboardingConfig?provider=AWS&scope=${var.scope}"

  request_headers = {
    X-Api-Key = var.castai_api_key
  }
}

check "onboarding_config_status" {
  assert {
    condition     = data.http.onboarding_config.status_code == 200
    error_message = "Failed to fetch onboarding config from Cast AI API (status: ${data.http.onboarding_config.status_code}). Check castai_api_url and castai_api_key."
  }
}

check "cur_s3_bucket_config" {
  assert {
    condition     = (var.cur_s3_bucket_name == "") == (var.cur_s3_bucket_region == "")
    error_message = "cur_s3_bucket_name and cur_s3_bucket_region must both be set or both be empty."
  }
}

check "onboarding_config_role_based" {
  assert {
    condition     = local.castai_aws_account_id != null
    error_message = "Onboarding config response does not include castAwsAccountId. Module v2 requires the role-based Cloud Connect backend; pin the module to the latest v1.x release for the legacy user-based backend."
  }
}

check "onboarding_config_has_permissions" {
  assert {
    condition = (
      length(try(local.onboarding_config.awsConfig.permissions, [])) > 0 ||
      length(try(local.onboarding_config.awsConfig.managedPolicies, [])) > 0
    )
    error_message = "Onboarding config returned no permissions and no managed policies for scope '${var.scope}'. The IAM role would have no access."
  }
}

locals {
  onboarding_config     = jsondecode(data.http.onboarding_config.response_body)
  castai_aws_account_id = try(local.onboarding_config.awsConfig.castAwsAccountId, null)
  castai_role_arn       = try(local.onboarding_config.awsConfig.castRoleArn, null)

  # CAP-217: customers trust the whole CAST AWS account (account-root principal),
  # guarded by ExternalId = organization ID. Survives CAST-side role renames/recreation.
  castai_account_root_arn = local.castai_aws_account_id != null ? "arn:aws:iam::${local.castai_aws_account_id}:root" : null

  api_permissions = try(local.onboarding_config.awsConfig.permissions, [])
  api_managed_policies = [
    for name in try(local.onboarding_config.awsConfig.managedPolicies, []) :
    "arn:aws:iam::aws:policy/${name}"
  ]
}
