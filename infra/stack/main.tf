# Composition root: wires the modules together for one environment.
#
#   network -> security -> database ----\
#      \            \                    -> compute (ECS + internal ALB) -> cdn (CloudFront + S3)
#       \--- kms ----\------------------/            \
#                                                     -> monitoring, backup

data "aws_ecr_repository" "api" {
  name = var.ecr_repository_name
}

# Shared secret between CloudFront and the ALB listener rule.
resource "random_password" "origin_verify" {
  length  = 40
  special = false
}

module "kms" {
  source      = "../modules/kms"
  name_prefix = local.name_prefix
}

module "network" {
  source                   = "../modules/network"
  name_prefix              = local.name_prefix
  vpc_cidr                 = var.vpc_cidr
  az_count                 = var.az_count
  nat_gateway_mode         = var.nat_gateway_mode
  flow_logs_retention_days = var.flow_logs_retention_days
  kms_key_arn              = module.kms.key_arn
}

module "security" {
  source      = "../modules/security"
  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}

module "database" {
  source                   = "../modules/database"
  name_prefix              = local.name_prefix
  subnet_ids               = module.network.data_subnet_ids
  security_group_id        = module.security.db_sg_id
  kms_key_arn              = module.kms.key_arn
  instance_class           = var.db_instance_class
  multi_az                 = var.db_multi_az
  backup_retention_days    = var.db_backup_retention_days
  deletion_protection      = var.db_deletion_protection
  skip_final_snapshot      = var.db_skip_final_snapshot
  max_allocated_storage_gb = var.db_max_allocated_storage_gb
  performance_insights     = var.db_performance_insights
}

module "compute" {
  source      = "../modules/compute"
  name_prefix = local.name_prefix
  environment = var.environment
  vpc_id      = module.network.vpc_id

  alb_subnet_ids = module.network.private_subnet_ids
  # Without NAT, tasks sit in public subnets with a public IP for egress only;
  # their SG still admits traffic from the ALB alone.
  task_subnet_ids  = module.network.has_nat ? module.network.private_subnet_ids : module.network.public_subnet_ids
  assign_public_ip = !module.network.has_nat

  alb_security_group_id = module.security.alb_sg_id
  app_security_group_id = module.security.app_sg_id

  image_repository_url = data.aws_ecr_repository.api.repository_url
  image_tag            = var.image_tag
  cpu                  = var.task_cpu
  memory               = var.task_memory
  min_tasks            = var.min_tasks
  max_tasks            = var.max_tasks
  container_insights   = var.container_insights
  log_retention_days   = var.log_retention_days
  deletion_protection  = var.db_deletion_protection # same switch protects the ALB

  db_host       = module.database.address
  db_port       = module.database.port
  db_name       = module.database.db_name
  db_username   = module.database.username
  db_secret_arn = module.database.master_secret_arn
  kms_key_arn   = module.kms.key_arn

  origin_verify_header_value = random_password.origin_verify.result
}

module "cdn" {
  source = "../modules/cdn"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
  name_prefix                = local.name_prefix
  alb_arn                    = module.compute.alb_arn
  alb_dns_name               = module.compute.alb_dns_name
  origin_verify_header_value = random_password.origin_verify.result
  enable_waf                 = var.enable_waf
}

module "monitoring" {
  source                  = "../modules/monitoring"
  name_prefix             = local.name_prefix
  alert_emails            = var.alert_emails
  kms_key_arn             = module.kms.key_arn
  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  ecs_cluster_name        = module.compute.cluster_name
  ecs_service_name        = module.compute.service_name
  api_log_group_name      = module.compute.log_group_name
  db_instance_id          = module.database.instance_id
}

module "backup" {
  source = "../modules/backup"
  providers = {
    aws             = aws
    aws.copy_region = aws.copy_region
  }
  name_prefix              = local.name_prefix
  environment              = var.environment
  daily_retention_days     = var.backup_daily_retention_days
  weekly_retention_days    = var.backup_weekly_retention_days
  enable_cross_region_copy = var.enable_cross_region_backup
  enable_vault_lock        = var.enable_backup_vault_lock
}
