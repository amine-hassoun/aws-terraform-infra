module "compute" {
  source = "./modules/compute"

  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  dynamodb_table_name = module.database.table_name
  common_tags         = local.common_tags
}

output "lambda_function_url" {
  description = "Public HTTPS entry point for the app Lambda"
  value       = module.compute.function_url
}
