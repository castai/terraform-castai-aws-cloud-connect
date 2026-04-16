resource "aws_iam_role" "castai_discovery" {
  name = var.role_name
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = local.castai_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.castai_organization_id
          }
        }
      }
    ]
  })
}

# Org management policy (only for org-scoped integrations)
resource "aws_iam_policy" "org_management" {
  count = local.is_management_account ? 1 : 0

  name = "castai-org-management-policy"
  tags = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeOrganization"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "org_management" {
  count = local.is_management_account ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = aws_iam_policy.org_management[0].arn
}

# Custom discovery policy (when using custom permissions, not managed policies)
resource "aws_iam_policy" "discovery" {
  count = length(local.selected_permissions) > 0 ? 1 : 0

  name = "castai-${lower(replace(var.scope, "_", "-"))}-readonly-policy"
  tags = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = local.selected_permissions
          Resource = "*"
        }
      ],
      local.cur_s3_statement
    )
  })
}

# Standalone S3 policy for scopes that use managed policies (e.g. ALL uses ReadOnlyAccess,
# which already includes S3, but we still scope it down to the specific CUR bucket).
resource "aws_iam_policy" "cur_s3" {
  count = var.cur_s3_bucket_name != "" && length(local.selected_permissions) == 0 ? 1 : 0

  name = "castai-cur-s3-readonly-policy"
  tags = var.tags

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.cur_s3_statement
  })
}

resource "aws_iam_role_policy_attachment" "cur_s3" {
  count = var.cur_s3_bucket_name != "" && length(local.selected_permissions) == 0 && local.attach_discovery_to_current ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = aws_iam_policy.cur_s3[0].arn
}

# Attach discovery permissions to the role in the current account:
#   Account-scoped:   always
#   Management (org): only if mgmt account is in the account list (or list is empty)
#   Multi-account:    only if current account is in the explicit list
locals {
  attach_discovery_to_current = (
    !local.is_management_account && !local.is_multi_account ||
    local.attach_discovery_to_management ||
    local.current_account_in_list
  )
}

# Attach custom discovery policy to role
resource "aws_iam_role_policy_attachment" "discovery" {
  count = length(local.selected_permissions) > 0 && local.attach_discovery_to_current ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = aws_iam_policy.discovery[0].arn
}

# Attach managed policies (e.g., ReadOnlyAccess for ALL scope)
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = local.attach_discovery_to_current ? toset(local.selected_managed_policies) : toset([])

  role       = aws_iam_role.castai_discovery.name
  policy_arn = each.value
}
