# Fetch structured onboarding config from the CAST AI API
data "http" "onboarding_config" {
  url = "${var.castai_api_url}/inventory/v1beta/organizations/${var.castai_organization_id}/cloud-asset-integrations:getOnboardingConfig?provider=AWS&scope=${var.scope}"

  request_headers = {
    X-Api-Key = var.castai_api_key
  }
}

check "onboarding_config_status" {
  assert {
    condition     = data.http.onboarding_config.status_code == 200
    error_message = "Failed to fetch onboarding config from CAST AI API (status: ${data.http.onboarding_config.status_code}). Check castai_api_url and castai_api_key."
  }
}

locals {
  onboarding_config = jsondecode(data.http.onboarding_config.response_body)
  castai_user_arn   = local.onboarding_config.awsConfig.castUserArn
  api_permissions   = try(local.onboarding_config.awsConfig.permissions, [])
  api_managed_policies = [
    for name in try(local.onboarding_config.awsConfig.managedPolicies, []) :
    "arn:aws:iam::aws:policy/${name}"
  ]
}
