output "table_name" {
  value = aws_dynamodb_table.items.name
}

output "table_arn" {
  value = aws_dynamodb_table.items.arn
}