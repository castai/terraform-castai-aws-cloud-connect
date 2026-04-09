# CloudFormation stack for EKS access entry configuration (account-scoped and multi-account current account)
# For org-scoped integrations, the Lambda is deployed via the StackSet in stackset.tf

locals {
  # IAM policy actions for the EKS access Lambda
  eks_lambda_iam_actions = ["ec2:DescribeRegions", "eks:ListClusters", "eks:DescribeCluster", "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry", "eks:AssociateAccessPolicy", "eks:ListAssociatedAccessPolicies"]

  # Shared Lambda function properties (everything except DependsOn and CAST_ROLE_ARN)
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

  # IAM role and trigger — identical in both standalone and stackset contexts
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

  # Standalone stack: role ARN from CFN parameter, Lambda depends on own IAM role
  eks_cfn_resources_standalone = merge(local.eks_cfn_role_and_trigger, {
    EksAccessLambda = {
      Type      = "AWS::Lambda::Function"
      DependsOn = ["EksAccessLambdaRole"]
      Properties = merge(local.eks_cfn_lambda_properties, {
        Environment = {
          Variables = {
            CAST_ROLE_ARN        = { Ref = "CastRoleArn" }
            ALLOWED_CLUSTER_ARNS = { Ref = "AllowedClusterArns" }
          }
        }
      })
    }
  })

  # StackSet: role ARN from same-stack resource, Lambda depends on discovery role
  eks_cfn_resources_stackset = merge(local.eks_cfn_role_and_trigger, {
    EksAccessLambda = {
      Type      = "AWS::Lambda::Function"
      DependsOn = ["CastDiscoveryRole"]
      Properties = merge(local.eks_cfn_lambda_properties, {
        Environment = {
          Variables = {
            CAST_ROLE_ARN        = { "Fn::GetAtt" = ["CastDiscoveryRole", "Arn"] }
            ALLOWED_CLUSTER_ARNS = { Ref = "AllowedClusterArns" }
          }
        }
      })
    }
  })

  # Python Lambda code for EKS access entry configuration
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
        role_arn = os.environ["CAST_ROLE_ARN"]
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

resource "aws_cloudformation_stack" "eks_access" {
  count = local.eks_enabled && !local.is_management_account && (!local.is_multi_account || local.current_account_in_list) ? 1 : 0

  name         = "${var.role_name}-eks-access"
  capabilities = ["CAPABILITY_NAMED_IAM"]
  tags         = var.tags

  parameters = {
    CastRoleArn        = aws_iam_role.castai_discovery.arn
    RoleName           = var.role_name
    AllowedClusterArns = local.eks_cluster_arns_csv
  }

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "CAST AI EKS access entry configuration"

    Parameters = {
      CastRoleArn = {
        Type        = "String"
        Description = "ARN of the CAST AI discovery role"
      }
      RoleName = {
        Type        = "String"
        Description = "IAM role name for discovery"
      }
      AllowedClusterArns = {
        Type        = "String"
        Description = "Comma-separated list of EKS cluster ARNs to configure access for (empty means all)"
        Default     = ""
      }
    }

    Resources = local.eks_cfn_resources_standalone
  })
}
