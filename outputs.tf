output "TOPIC_ARN" {
  value = aws_sns_topic.get-hello.arn
}

output "FUNCTION_NAME" {
  value = aws_lambda_function.hello.function_name
}

output "SCHEDULE_NAME" {
  value = aws_scheduler_schedule.daily.name
}

output "ROLE_NAME" {
    value = aws_iam_role.lambda.name
}

output "ALERT_TOPIC_ARN" {
  value = aws_sns_topic.alerts.arn
}