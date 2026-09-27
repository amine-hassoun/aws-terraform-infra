data "aws_region" "current" {}

# --- SNS topic + email subscription for alarm notifications ---
resource "aws_sns_topic" "alerts" {
  name              = "aws-terraform-infra-alerts"
  tags              = var.common_tags
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Lambda Errors: any error at all ---
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "aws-terraform-infra-lambda-errors"
  alarm_description   = "Lambda returned one or more errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

# --- Lambda Throttles ---
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "aws-terraform-infra-lambda-throttles"
  alarm_description   = "Lambda invocations are being throttled"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

# --- DynamoDB Throttled Requests ---
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "aws-terraform-infra-dynamodb-throttles"
  alarm_description   = "DynamoDB is throttling requests - provisioned capacity may be too low"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ThrottledRequests"
  dimensions          = { TableName = var.dynamodb_table_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

# --- Dashboard: single-pane Lambda + DynamoDB health ---
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "aws-terraform-infra-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Lambda - Invocations, Errors, Throttles"
          view   = "timeSeries"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_function_name]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Lambda - Duration (avg / p99)"
          view   = "timeSeries"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p99" }]
          ]
          period = 300
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "DynamoDB - Consumed Capacity"
          view   = "timeSeries"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "DynamoDB - Throttled Requests"
          view    = "timeSeries"
          region  = data.aws_region.current.name
          metrics = [["AWS/DynamoDB", "ThrottledRequests", "TableName", var.dynamodb_table_name]]
          period  = 300
          stat    = "Sum"
        }
      }
    ]
  })
}