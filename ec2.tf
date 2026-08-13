data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "terraform-practice-ec2"
  description = "No inbound access; management is via SSM Session Manager only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound (package installs, New Relic, SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-practice-ec2"
  }
}

resource "aws_iam_role" "ec2" {
  name = "terraform-practice-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "read_new_relic_key" {
  name = "read-new-relic-api-key"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadParameter"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.new_relic_api_key.arn
      },
      {
        Sid      = "DecryptParameter"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.ap-northeast-1.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "terraform-practice-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_ssm_parameter" "new_relic_api_key" {
  name  = "/terraform-practice/new-relic/api-key"
  type  = "SecureString"
  value = var.new_relic_api_key
}

resource "aws_instance" "test" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eu
    NEW_RELIC_API_KEY=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.new_relic_api_key.name}" \
      --with-decryption \
      --region ap-northeast-1 \
      --query 'Parameter.Value' \
      --output text)

    curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash
    NEW_RELIC_API_KEY="$NEW_RELIC_API_KEY" NEW_RELIC_ACCOUNT_ID="${var.new_relic_account_id}" \
      /usr/local/bin/newrelic install -y
  EOF

  tags = {
    Name = "terraform-practice-test"
  }
}
