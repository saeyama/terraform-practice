data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-practice"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud"        = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:repository" = "saeyama/terraform-practice"
          }
          StringLike = {
            # GitHub repos created after 2026-07-15 embed immutable owner/repo IDs in `sub`
            # (repo:owner@ownerId/repo@repoId:...). AWS requires a non-wildcard-only `sub`
            # condition on this provider, so this is kept as defense-in-depth alongside
            # the `repository` claim above, which is the actual access boundary.
            "token.actions.githubusercontent.com:sub" = "repo:saeyama@*/terraform-practice@*:*"
          }
        }
      }
    ]
  })
}

# Scoped to the resources this repo currently manages (main.tf) plus the state bucket.
# Extend this policy as new resource types are added to the Terraform config.
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = "arn:aws:s3:::terraform-practice-tfstate-540444578784"
      },
      {
        Sid    = "TerraformStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::terraform-practice-tfstate-540444578784/terraform-practice/*"
      },
      {
        Sid    = "LambdaManage"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:ListVersionsByFunction",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags",
        ]
        Resource = "arn:aws:lambda:ap-northeast-1:${data.aws_caller_identity.current.account_id}:function:lambda-practice"
      },
      {
        Sid    = "IamRoleManage"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/lambda-practice-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/terraform-practice-ec2-role",
        ]
      },
      {
        Sid    = "IamPolicyAttach"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:GetPolicy",
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/lambda-practice-role",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/terraform-practice-ec2-role",
          "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
          "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        ]
      },
      {
        Sid    = "IamInstanceProfileManage"
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/terraform-practice-ec2-profile"
      },
      {
        Sid      = "Ec2Manage"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "ap-northeast-1"
          }
        }
      },
      {
        Sid    = "SsmParameterManage"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:ListTagsForResource",
        ]
        Resource = "arn:aws:ssm:ap-northeast-1:${data.aws_caller_identity.current.account_id}:parameter/terraform-practice/*"
      },
      {
        # DescribeParameters has no resource-level permission support; AWS requires Resource "*".
        Sid      = "SsmDescribeParameters"
        Effect   = "Allow"
        Action   = "ssm:DescribeParameters"
        Resource = "*"
      },
      {
        Sid      = "StsIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid    = "FlowLogsBucketManage"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::terraform-practice-vpc-flow-logs-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::terraform-practice-vpc-flow-logs-${data.aws_caller_identity.current.account_id}/*",
        ]
      },
      {
        # Log Delivery actions have no resource-level permission support; AWS requires Resource "*".
        # Needed to create/manage the VPC Flow Log even though its destination is S3, not CloudWatch Logs.
        Sid    = "FlowLogsDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DescribeLogGroups",
          "logs:DescribeResourcePolicies",
          "logs:GetLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
        ]
        Resource = "*"
      },
      {
        Sid    = "AthenaResultsBucketManage"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::terraform-practice-athena-results-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::terraform-practice-athena-results-${data.aws_caller_identity.current.account_id}/*",
        ]
      },
      {
        Sid    = "AthenaWorkgroupManage"
        Effect = "Allow"
        Action = [
          "athena:CreateWorkGroup",
          "athena:DeleteWorkGroup",
          "athena:GetWorkGroup",
          "athena:UpdateWorkGroup",
          "athena:TagResource",
          "athena:UntagResource",
          "athena:ListTagsForResource",
        ]
        Resource = "arn:aws:athena:ap-northeast-1:${data.aws_caller_identity.current.account_id}:workgroup/terraform-practice"
      },
      {
        Sid    = "GlueCatalogManage"
        Effect = "Allow"
        Action = [
          "glue:CreateDatabase",
          "glue:DeleteDatabase",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:UpdateDatabase",
          "glue:CreateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:UpdateTable",
        ]
        Resource = [
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:database/terraform_practice_flow_logs",
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:table/terraform_practice_flow_logs/*",
        ]
      },
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
