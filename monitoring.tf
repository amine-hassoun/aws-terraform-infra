module "monitoring" {
  source               = "./modules/monitoring"
  lambda_function_name = module.compute.function_name
  dynamodb_table_name  = module.database.table_name
  alert_email          = var.alert_email
  common_tags          = local.common_tags
}