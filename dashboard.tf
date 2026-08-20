resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "terraform-practice"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2: CPU Utilization"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.test.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2: Network In/Out"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.test.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.test.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EC2: Status Check Failed"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.test.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions: Daily Flow Log Check"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Sum"
          period = 86400
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.daily_flow_log_check.arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.daily_flow_log_check.arn]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "SNS: Flow Log Alerts"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Sum"
          period = 86400
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.flow_log_alerts.name],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", aws_sns_topic.flow_log_alerts.name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "EC2: Memory & Disk Utilization (CWAgent)"
          region = "ap-northeast-1"
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.test.id],
            # Root volume dimensions (path/device/fstype) are fixed at the values
            # reported by CWAgent on this instance; a replaced instance with a
            # different device name would need these updated.
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.test.id, "path", "/", "device", "nvme0n1p1", "fstype", "xfs"]
          ]
        }
      }
    ]
  })
}
