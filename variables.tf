variable "new_relic_api_key" {
  description = "New Relic User API key, used to install and connect the Infrastructure agent"
  type        = string
  sensitive   = true
}

variable "new_relic_account_id" {
  description = "New Relic account ID to report metrics to"
  type        = string
}

variable "alert_notification_email" {
  description = "Email address to receive VPC Flow Logs REJECT count anomaly alerts"
  type        = string
  sensitive   = true
}
