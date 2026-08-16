# EventBridge Scheduler triggers a Step Functions state machine that runs an
# Athena query for yesterday's REJECT count and emails an SNS alert if the
# count is above the threshold.

# Set low deliberately so we can confirm the notification path actually
# fires; raise this once real anomaly behavior is understood.
locals {
  reject_count_alert_threshold = 100
}

resource "aws_sns_topic" "flow_log_alerts" {
  name = "terraform-practice-flow-log-alerts"
}

resource "aws_sns_topic_subscription" "flow_log_alerts_email" {
  topic_arn = aws_sns_topic.flow_log_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_notification_email
}

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
          "athena:GetQueryResults",
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

resource "aws_iam_role_policy" "step_functions_sns" {
  name = "publish-sns-alert"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishAlert"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.flow_log_alerts.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "daily_flow_log_check" {
  name     = "terraform-practice-daily-flow-log-check"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Daily VPC Flow Logs REJECT check: run the Athena query, then email an SNS alert if the count is above the threshold"
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
        Next = "GetQueryResults"
      }
      GetQueryResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:getQueryResults"
        Parameters = {
          "QueryExecutionId.$" = "$.QueryExecution.QueryExecutionId"
        }
        Next = "ExtractRejectCount"
      }
      ExtractRejectCount = {
        Type = "Pass"
        Parameters = {
          "reject_count.$" = "States.StringToJson($.ResultSet.Rows[1].Data[0].VarCharValue)"
        }
        Next = "CheckThreshold"
      }
      CheckThreshold = {
        Type = "Choice"
        Choices = [
          {
            Variable           = "$.reject_count"
            NumericGreaterThan = local.reject_count_alert_threshold
            Next               = "NotifyHighRejectCount"
          }
        ]
        Default = "NoAlertNeeded"
      }
      NoAlertNeeded = {
        Type = "Pass"
        End  = true
      }
      NotifyHighRejectCount = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.flow_log_alerts.arn
          Subject     = "VPC Flow Logs REJECT count alert"
          "Message.$" = "States.Format('VPC Flow Logs REJECT count for yesterday was {}, above the threshold of ${local.reject_count_alert_threshold}.', $.reject_count)"
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
