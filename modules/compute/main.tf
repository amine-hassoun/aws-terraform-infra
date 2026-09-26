data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- Security group for the Lambda ENI inside the VPC ---
resource "aws_security_group" "lambda" {
  name        = "aws-terraform-infra-lambda-sg"
  description = "Lambda ENI - outbound only, no inbound needed"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound - actual reachability is scoped by the private route table, not this rule"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "aws-terraform-infra-lambda-sg"
  })
}

# --- IAM: trust policy allowing the Lambda service to assume this role ---
resource "aws_iam_role" "lambda_execution" {
  name = "aws-terraform-infra-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

# --- IAM: least-privilege DynamoDB access, scoped to this one table's ARN ---
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-app-table-access"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ]
      Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
    }]
  })
}

# --- IAM: managed policies required for a VPC-attached function ---
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- Package the handler source into a deployable zip ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda.zip"
}

# --- The function itself ---
resource "aws_lambda_function" "app" {
  function_name                  = "aws-terraform-infra-app"
  role                           = aws_iam_role.lambda_execution.arn
  handler                        = "index.handler"
  runtime                        = "nodejs22.x"
  timeout                        = 10
  memory_size                    = 128

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }

  tags = var.common_tags
}

# --- Public HTTPS entry point - no API Gateway, no ALB ---
resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_methods = ["GET", "POST"]
    allow_origins = ["*"]
  }
}

# --- Resource-based policy: without this, authorization_type = "NONE" above
# still isn't enough - Lambda separately requires an explicit statement
# granting public invoke access on the function itself. ---
resource "aws_lambda_permission" "function_url_public" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "function_public" {
  statement_id  = "AllowPublicInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "*"
}
