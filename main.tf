############################################################
########## Daily "Hello, world!" email #####################
############################################################

terraform {
  required_version = ">= 1.5"
}

provider "aws" {
  region = var.REGION
}

############################################################
######### SNS topic ########################################
############################################################

# Creates the initial SNS topic and reads any emails that 
# were put int the SUBSCRIBER_EMAILS variable.
resource "aws_sns_topic" "get-hello" {
  name = var.TOPIC_NAME
}

# Leave subscriber_emails empty to subscribe by hand in the console,
# as the assignment describes.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.SUBSCRIBER_EMAILS)

  topic_arn = aws_sns_topic.get-hello.arn
  protocol  = "email"
  endpoint  = each.key #Goes through the for-each list and adds it to the list.
}

############################################################
########## Lambda: package the code ########################
############################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

##############################################################
########## Lambda ############################################
##############################################################

## Creates the json output which will later be inserted into the policy
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Create a role and attach the above data to it.
resource "aws_iam_role" "lambda" {
  name               = "${var.FUNCTION_NAME}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Lets the function write its logs to CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allows the Labmda function to publish to the topic. Otherewise you get a permission error.
data "aws_iam_policy_document" "publish_to_topic" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.get-hello.arn]
  }
}

resource "aws_iam_role_policy" "lambda_publish" {
  name   = "publish-to-${var.TOPIC_NAME}"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.publish_to_topic.json
}

############################################################
########## Lambda: log group + function ####################
############################################################

# Log retention is set here. Otherwise logs will keep piling up.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.FUNCTION_NAME}"
  retention_in_days = var.LOG_RETENTION
}

resource "aws_lambda_function" "hello" {
  function_name = var.FUNCTION_NAME
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.14"
  # Which function will be run from the uploaded file:
  # <lambda_function: lambda_function.py>.<function name: def lambda_handler>
  handler       = "lambda_function.lambda_handler" 
  timeout       = 5

  filename         = data.archive_file.lambda.output_path

  # Terraform compares this fingerprint with the last one. If your Python changes, 
  # the hash changes and Terraform redeploys. Without it, code edits would not trigger an update.
  source_code_hash = data.archive_file.lambda.output_base64sha256

  # Avoid hard coding the Arn Topic in Python. Instead put it in the Lambda env variable.
  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.get-hello.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_logs,
  ]
}

####################################################################
########## EventBridge Scheduler ###################################
####################################################################

# Role that defines what the scheduler may do.
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.SCHEDULE_NAME}-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "invoke_lambda" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.hello.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "invoke-${var.FUNCTION_NAME}"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.invoke_lambda.json
}

############################################################
########## EventBridge Scheduler ###########################
############################################################

# Creates the schedule itself.
resource "aws_scheduler_schedule" "daily" {
  name       = var.SCHEDULE_NAME
  group_name = "default"

  flexible_time_window {
    mode = "OFF" # run exactly on time
  }

  schedule_expression          = var.SCHEDULE_EXPRESSION
  schedule_expression_timezone = var.SCHEDULE_TIMEZONE

  target {
    arn      = aws_lambda_function.hello.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({}) # the function ignores its event
  }

  depends_on = [aws_iam_role_policy.scheduler_invoke]
}


############################################################
########## ALERTING TOPIC ##################################
############################################################
resource "aws_sns_topic" "alerts" {
  name = "${var.TOPIC_NAME}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  for_each = toset(var.ALERT_EMAILS)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}


############################################################
########## Alarm 1: "Ran with errors or failed." ###########
############################################################

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "${var.FUNCTION_NAME}-errors"
  alarm_description = "The Lambda function raised an error or timed out."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.hello.function_name
  }

  statistic           = "Sum"
  period              = 300 # look at 5-minute windows
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}

############################################################
########## Alarm 2: Did not run in the past 24 hours #######
############################################################

resource "aws_cloudwatch_metric_alarm" "lambda_not_running" {
  alarm_name        = "${var.FUNCTION_NAME}-not-running"
  alarm_description = "The Lambda function has not been invoked for 24 hours."

  namespace   = "AWS/Lambda"
  metric_name = "Invocations"
  dimensions = {
    FunctionName = aws_lambda_function.hello.function_name
  }

  statistic           = "Sum"
  period              = 3600 # 1-hour windows
  evaluation_periods  = 24
  datapoints_to_alarm = 24 # ALL 24 windows must be empty
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  # Silence is failure.
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}