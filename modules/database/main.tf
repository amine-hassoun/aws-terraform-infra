resource "aws_dynamodb_table" "items" {
  name           = "aws-terraform-infra-app-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = var.common_tags
}