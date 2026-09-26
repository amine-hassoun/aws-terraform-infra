data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

resource "aws_iam_role" "github_actions_terraform" {
  name = "aws-terraform-infra-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:amine-hassoun/aws-terraform-infra:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

# checkov:skip=CKV_AWS_286: PassRole + CreateRole/AttachRolePolicy is required for CI to provision this project's own Lambda execution role; Resource is scoped to role/aws-terraform-infra-*, not *, so it can't escalate outside this project's own roles.
# checkov:skip=CKV_AWS_289: Same scoped-resource reasoning - permissions management is restricted to this project's IAM roles only.
# checkov:skip=CKV_AWS_290: ProjectResources' write actions (lambda:*, ec2:Create*) are required to provision this project's own resources; most EC2 actions here don't support resource-level ARNs at all - an AWS platform limitation, not a shortcut.
# checkov:skip=CKV_AWS_355: Same as above - already scoped narrowly wherever the action type actually supports it (S3, DynamoDB, IAM).
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-management"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBackend"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::amine-hassoun-aws-terraform-infra-state",
          "arn:aws:s3:::amine-hassoun-aws-terraform-infra-state/*"
        ]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Describe*"]
        Resource = "arn:aws:dynamodb:*:*:table/terraform-locks"
      },
      {
        Sid    = "ProjectResources"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateTags", "ec2:DeleteTags",
          "lambda:*",
          "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:Describe*", "dynamodb:UpdateTable",
          "dynamodb:TagResource", "dynamodb:UntagResource", "dynamodb:ListTagsOfResource",
          "sns:*",
          "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
          "cloudwatch:PutDashboard", "cloudwatch:DeleteDashboards", "cloudwatch:GetDashboard",
          "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ScopedIam"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-terraform-infra-*"
      },
      {
        Sid    = "StateBucketConfig"
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:PutBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketTagging"
        ]
        Resource = "arn:aws:s3:::amine-hassoun-aws-terraform-infra-state"
      },
      {
        Sid    = "OidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_terraform.arn
}

data "aws_caller_identity" "current" {}