# EKS access entry configuration for k8s object sync.
# When eks_k8s_sync_enabled is true, the module discovers clusters and creates
# access entries so CAST AI can read k8s objects via the EKS API.
#
# Cluster discovery:
#   - If eks_cluster_arns is empty: discovers all clusters in the current region
#   - If eks_cluster_arns is set: only configures the specified clusters

locals {
  eks_enabled = var.eks_k8s_sync_enabled && contains(["ALL", "ALL_MINIMAL_PERMISSIONS"], var.scope)

  # Derive cluster names from provided ARNs (format: arn:aws:eks:<region>:<account>:cluster/<name>)
  eks_cluster_names_from_arns = toset([
    for arn in var.eks_cluster_arns : split("/", arn)[1]
  ])

  # Use provided cluster names or fall back to all discovered clusters
  eks_cluster_names = local.eks_enabled ? (
    length(var.eks_cluster_arns) > 0
    ? local.eks_cluster_names_from_arns
    : toset(data.aws_eks_clusters.all[0].names)
  ) : toset([])
}

data "aws_eks_clusters" "all" {
  count = local.eks_enabled && length(var.eks_cluster_arns) == 0 ? 1 : 0
}

resource "aws_eks_access_entry" "castai" {
  for_each = local.eks_cluster_names

  cluster_name  = each.value
  principal_arn = aws_iam_role.castai_discovery.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "castai" {
  for_each = local.eks_cluster_names

  cluster_name  = each.value
  principal_arn = aws_iam_role.castai_discovery.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.castai]
}
