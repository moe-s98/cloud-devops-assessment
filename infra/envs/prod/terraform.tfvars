# prod: highly available and protected. Same code as dev, different values.
environment = "prod"
vpc_cidr    = "10.30.0.0/16"
az_count    = 3

nat_gateway_mode = "per_az" # tasks in private subnets, one NAT per AZ

task_cpu           = 512
task_memory        = 1024
min_tasks          = 2 # one task per AZ minimum, no cold path
max_tasks          = 10
container_insights = true

db_instance_class           = "db.t4g.medium"
db_performance_insights     = true
db_multi_az                 = true # synchronous standby, automatic failover
db_backup_retention_days    = 14
db_deletion_protection      = true
db_skip_final_snapshot      = false
db_max_allocated_storage_gb = 100

enable_waf                   = true
backup_daily_retention_days  = 14
backup_weekly_retention_days = 90
enable_cross_region_backup   = true
backup_copy_region           = "eu-central-1"
enable_backup_vault_lock     = true

log_retention_days       = 90
flow_logs_retention_days = 30
