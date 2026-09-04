variable "lambda_function_name" {
  description = "Name of the Lambda function to alarm on"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table to alarm on"
  type        = string
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

variable "common_tags" {
  description = "Common resource tags"
  type        = map(string)
}