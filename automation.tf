# Skeleton: EventBridge Scheduler triggers a Step Functions state machine.
# The state machine currently just returns a fixed message (Pass state) so we
# can verify the trigger -> execution wiring before adding the real Athena
# query logic.

resource "aws_iam_role" "step_functions" {
  name = "terraform-practice-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "states.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_athena" {
  name = "run-athena-query"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQuery"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:StopQueryExecution",
        ]
        Resource = aws_athena_workgroup.main.arn
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:GetPartitions",
        ]
        Resource = [
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:database/terraform_practice_flow_logs",
          "arn:aws:glue:ap-northeast-1:${data.aws_caller_identity.current.account_id}:table/terraform_practice_flow_logs/*",
        ]
      },
      {
        Sid    = "AthenaResultsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*",
        ]
      },
      {
        Sid    = "FlowLogsBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.flow_logs.arn,
          "${aws_s3_bucket.flow_logs.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_sfn_state_machine" "daily_flow_log_check" {
  name     = "terraform-practice-daily-flow-log-check"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Daily VPC Flow Logs REJECT check: run the Athena query and wait for it to finish (SNS notification added next)"
    StartAt = "RunAthenaQuery"
    States = {
      RunAthenaQuery = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.flow_logs.name
          }
          QueryString = "SELECT COUNT(*) AS reject_count FROM vpc_flow_logs WHERE action = 'REJECT' AND day = date_format(date_add('day', -1, current_date), '%Y/%m/%d')"
          WorkGroup   = aws_athena_workgroup.main.name
        }
        End = true
      }
    }
  })
}

resource "aws_iam_role" "scheduler" {
  name = "terraform-practice-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "scheduler.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler_start_execution" {
  name = "start-execution"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.daily_flow_log_check.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "daily_flow_log_check" {
  name = "terraform-practice-daily-flow-log-check"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 9 * * ? *)"
  schedule_expression_timezone = "Asia/Tokyo"

  target {
    arn      = aws_sfn_state_machine.daily_flow_log_check.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}
