# EKS access entry configuration for k8s object sync.
#
# Account-scoped: native Terraform resources (aws_eks_access_entry + aws_eks_access_policy_association)
# Org-scoped / multi-account: Lambda deployed via CloudFormation StackSet in stackset.tf,
#   since Terraform cannot create resources in member accounts directly.

locals {
  # Derive cluster names from provided ARNs (format: arn:aws:eks:<region>:<account>:cluster/<name>)
  eks_cluster_names_from_arns = toset([
    for arn in var.eks_cluster_arns : split("/", arn)[1]
  ])

  # For account-scoped: use provided cluster names or discover all clusters in the current region
  eks_cluster_names = local.eks_enabled && !local.is_management_account && (!local.is_multi_account || local.current_account_in_list) ? (
    length(var.eks_cluster_arns) > 0
    ? local.eks_cluster_names_from_arns
    : toset(data.aws_eks_clusters.all[0].names)
  ) : toset([])

  # StackSet Lambda locals — used by stackset.tf for org-scoped / multi-account deployments

  # IAM policy actions for the EKS access Lambda
  eks_lambda_iam_actions = ["ec2:DescribeRegions", "eks:ListClusters", "eks:DescribeCluster", "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry", "eks:AssociateAccessPolicy", "eks:ListAssociatedAccessPolicies"]

  # Shared Lambda function properties
  eks_cfn_lambda_properties = {
    FunctionName = { "Fn::Sub" = "$${RoleName}-eks-access" }
    Runtime      = "python3.11"
    Handler      = "index.handler"
    Timeout      = 300
    MemorySize   = 256
    Role         = { "Fn::GetAtt" = ["EksAccessLambdaRole", "Arn"] }
    Code = {
      ZipFile = local.eks_lambda_code
    }
  }

  # IAM role and trigger — used in the StackSet template
  eks_cfn_role_and_trigger = {
    EksAccessLambdaRole = {
      Type = "AWS::IAM::Role"
      Properties = {
        RoleName = { "Fn::Sub" = "$${RoleName}-eks-lambda" }
        AssumeRolePolicyDocument = {
          Version = "2012-10-17"
          Statement = [
            {
              Effect    = "Allow"
              Principal = { Service = "lambda.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }
          ]
        }
        ManagedPolicyArns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
        Policies = [
          {
            PolicyName = "eks-access-management"
            PolicyDocument = {
              Version = "2012-10-17"
              Statement = [
                {
                  Effect   = "Allow"
                  Action   = local.eks_lambda_iam_actions
                  Resource = "*"
                }
              ]
            }
          }
        ]
      }
    }
    EksAccessTrigger = {
      Type      = "Custom::EksAccessConfiguration"
      DependsOn = ["EksAccessLambda"]
      Properties = {
        ServiceToken = { "Fn::GetAtt" = ["EksAccessLambda", "Arn"] }
      }
    }
  }

  # Stored as JSON string to avoid Terraform's conditional type-unification errors.
  # Consumer (stackset.tf) uses jsondecode().
  eks_cfn_resources_stackset = local.eks_enabled ? jsonencode(merge(local.eks_cfn_role_and_trigger, {
    EksAccessLambda = {
      Type      = "AWS::Lambda::Function"
      DependsOn = ["CastDiscoveryRole"]
      Properties = merge(local.eks_cfn_lambda_properties, {
        Environment = {
          Variables = {
            Cast_ROLE_ARN        = { "Fn::GetAtt" = ["CastDiscoveryRole", "Arn"] }
            ALLOWED_CLUSTER_ARNS = { Ref = "AllowedClusterArns" }
          }
        }
      })
    }
  })) : jsonencode({})

  eks_lambda_code = <<-PYTHON
import boto3
import json
import urllib.request
import os

def send_cfn_response(event, context, status, data=None):
    body = json.dumps({"Status": status, "Reason": "See CloudWatch", "PhysicalResourceId": context.log_stream_name, "StackId": event["StackId"], "RequestId": event["RequestId"], "LogicalResourceId": event["LogicalResourceId"], "Data": data or {}}).encode()
    req = urllib.request.Request(event["ResponseURL"], data=body, headers={"Content-Type": ""}, method="PUT")
    urllib.request.urlopen(req)

def get_allowed_arns():
    allowed = os.environ.get("ALLOWED_CLUSTER_ARNS", "")
    return set(allowed.split(",")) if allowed else None

def is_cluster_allowed(cluster_arn, allowed_arns):
    if allowed_arns is None:
        return True
    return cluster_arn in allowed_arns

def handler(event, context):
    print(f"Event: {json.dumps(event)}")
    try:
        role_arn = os.environ["Cast_ROLE_ARN"]
        if event.get("RequestType") == "Delete":
            result = cleanup_all_clusters(role_arn)
        else:
            result = configure_all_clusters(role_arn)
        send_cfn_response(event, context, "SUCCESS", result)
    except Exception as e:
        print(f"Error: {e}")
        # Always succeed on Delete to not block stack deletion
        if event.get("RequestType") == "Delete":
            send_cfn_response(event, context, "SUCCESS", {"Error": str(e)})
        else:
            send_cfn_response(event, context, "FAILED", {"Error": str(e)})

def scan_clusters(role_arn, action_fn):
    ec2 = boto3.client("ec2")
    sts = boto3.client("sts")
    account_id = sts.get_caller_identity()["Account"]
    allowed_arns = get_allowed_arns()
    processed, failed, skipped = [], [], []
    regions = [r["RegionName"] for r in ec2.describe_regions()["Regions"]]
    print(f"Scanning {len(regions)} regions for EKS clusters")
    for region in regions:
        try:
            eks = boto3.client("eks", region_name=region)
            for page in eks.get_paginator("list_clusters").paginate():
                for c in page["clusters"]:
                    cluster_arn = f"arn:aws:eks:{region}:{account_id}:cluster/{c}"
                    if not is_cluster_allowed(cluster_arn, allowed_arns):
                        print(f"Skipping cluster {c} - ARN {cluster_arn} not in allowed list")
                        skipped.append(cluster_arn)
                        continue
                    if action_fn(c, region, role_arn):
                        processed.append(cluster_arn)
                    else:
                        failed.append(cluster_arn)
        except Exception as e:
            print(f"Error scanning region {region}: {e}")
    return {"processed": processed, "failed": failed, "skipped": skipped}

def configure_all_clusters(role_arn):
    return scan_clusters(role_arn, configure_cluster)

def cleanup_all_clusters(role_arn):
    return scan_clusters(role_arn, cleanup_cluster)

def configure_cluster(name, region, role_arn):
    eks = boto3.client("eks", region_name=region)
    policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
    try:
        eks.describe_access_entry(clusterName=name, principalArn=role_arn)
        print(f"Access entry exists for {name}")
    except eks.exceptions.ResourceNotFoundException:
        try:
            eks.create_access_entry(clusterName=name, principalArn=role_arn, type="STANDARD")
            print(f"Created access entry for {name}")
        except Exception as e:
            print(f"Failed to create access entry for {name}: {e}")
            return False
    except Exception as e:
        print(f"Skipping {name}: {e}")
        return False
    try:
        resp = eks.list_associated_access_policies(clusterName=name, principalArn=role_arn)
        if policy not in [p["policyArn"] for p in resp.get("associatedAccessPolicies", [])]:
            eks.associate_access_policy(clusterName=name, principalArn=role_arn, policyArn=policy, accessScope={"type": "cluster"})
            print(f"Associated policy for {name}")
    except Exception as e:
        print(f"Failed to associate policy for {name}: {e}")
        return False
    return True

def cleanup_cluster(name, region, role_arn):
    eks = boto3.client("eks", region_name=region)
    try:
        eks.delete_access_entry(clusterName=name, principalArn=role_arn)
        print(f"Deleted access entry for {name}")
    except eks.exceptions.ResourceNotFoundException:
        print(f"Access entry already gone for {name}")
    except Exception as e:
        print(f"Failed to delete access entry for {name}: {e}")
        return False
    return True
PYTHON
}

# Account-scoped EKS access entries — created directly via Terraform native resources.
# For org-scoped / multi-account, the Lambda in the StackSet (stackset.tf) handles this.

data "aws_eks_clusters" "all" {
  count = local.eks_enabled && !local.is_management_account && (!local.is_multi_account || local.current_account_in_list) && length(var.eks_cluster_arns) == 0 ? 1 : 0
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
