output "function_url" {
  description = "Public HTTPS endpoint for the Lambda function"
  value       = aws_lambda_function_url.app.function_url
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}