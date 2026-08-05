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
        Sid      = "StsIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
