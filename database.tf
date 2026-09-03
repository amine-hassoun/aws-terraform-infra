module "database" {
  source       = "./modules/database"
  common_tags  = local.common_tags
}