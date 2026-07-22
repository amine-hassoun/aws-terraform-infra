variable "vpc_id" {
  description = "VPC ID the Lambda security group is created in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs the Lambda function is attached to"
  type        = list(string)
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB app table this function reads/writes. Must match the table Step 4 creates on Day 27."
  type        = string
  default     = "aws-terraform-infra-app-table"
}

variable "common_tags" {
  description = "Common resource tags"
  type        = map(string)
}
