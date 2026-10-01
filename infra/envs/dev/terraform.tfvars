# dev: lowest cost. Single small task, no NAT, no Multi-AZ, no WAF.
environment = "dev"
vpc_cidr    = "10.20.0.0/16"
az_count    = 2

nat_gateway_mode = "none"

task_cpu    = 256
task_memory = 512
min_tasks   = 1
max_tasks   = 3

db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 7
db_deletion_protection   = false
db_skip_final_snapshot   = true

enable_waf                   = false
backup_daily_retention_days  = 7
backup_weekly_retention_days = 0
enable_cross_region_backup   = false
enable_backup_vault_lock     = false

log_retention_days       = 14
flow_logs_retention_days = 7
