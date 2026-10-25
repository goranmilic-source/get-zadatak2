variable "REGION" {
  description = "Region for ALL resources. Scheduler, Lambda and SNS must share it."
  type        = string
  default     = "eu-west-1"
}

variable "TOPIC_NAME" {
  type    = string
  default = "GET-hello-world-topic"
}

variable "FUNCTION_NAME" {
  type    = string
  default = "GET-hello-world-function"
}

variable "SCHEDULE_NAME" {
  type    = string
  default = "GET-hello-world-daily"
}

variable "LOG_RETENTION" {
    type = number
    default = 7
}

variable "SCHEDULE_EXPRESSION" {
  description = "EventBridge cron/rate expression. Use rate(5 minutes) while testing."
  type        = string
  default     = "cron(0 1 * * ? *)" # every day at 01:00
  #default     = "cron(*/1 * * * ? *)" # Every 1 minute for testing
}

variable "SCHEDULE_TIMEZONE" {
  description = "IANA time zone the cron expression is evaluated in."
  type        = string
  default     = "Europe/Belgrade"
}

variable "SUBSCRIBER_EMAILS" {
  description = "Optional. Emails to subscribe from Terraform. Each one must still click the confirmation link."
  type        = list(string)
  default     = []
}

##### Is it ever a good idea to build anything without alerting?
variable "ALERT_EMAILS" {
  description = "Emails of the Admin group that receive ALARM notifications. Emails must confirm subscription."
  type        = list(string)
  default     = []
}