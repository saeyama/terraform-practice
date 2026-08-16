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

resource "aws_sfn_state_machine" "daily_flow_log_check" {
  name     = "terraform-practice-daily-flow-log-check"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Daily VPC Flow Logs REJECT check (skeleton, logic added next)"
    StartAt = "Placeholder"
    States = {
      Placeholder = {
        Type   = "Pass"
        Result = "Hello from Step Functions"
        End    = true
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
