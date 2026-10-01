# Three subnet tiers per AZ:
#   public  - internet-facing; NAT gateways (if any) and, in "none" mode, app tasks
#   private - internal ALB and (with NAT) app tasks; egress via NAT only
#   data    - RDS only; no route to the internet at all
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 -> /20 subnets: public 0-2, private 4-6, data 8-10
  public_cidrs  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_cidrs = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 4)]
  data_cidrs    = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  nat_count = { none = 0, single = 1, per_az = var.az_count }[var.nat_gateway_mode]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# Remove all rules from the default SG so nothing can accidentally use it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-default-deny" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# ---- Subnets ----------------------------------------------------------------
resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]
  # Public IPs are assigned explicitly per ECS service, never by default.
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-private-${local.azs[count.index]}", Tier = "private" }
}

resource "aws_subnet" "data" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-data-${local.azs[count.index]}", Tier = "data" }
}

# ---- Routing ----------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name_prefix}-nat-${local.azs[count.index]}" }
  depends_on    = [aws_internet_gateway.this]
}

# One private route table per AZ so per-AZ NAT keeps traffic in-zone.
resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-private-rt-${local.azs[count.index]}" }
}

resource "aws_route" "private_nat" {
  count                  = local.nat_count > 0 ? length(local.azs) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[min(count.index, local.nat_count - 1)].id
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Data tier: local routes only.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-data-rt" }
}

resource "aws_route_table_association" "data" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# Free gateway endpoint: ECR image layers (S3) never leave the AWS network.
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], aws_route_table.private[*].id)
  tags              = { Name = "${var.name_prefix}-s3-endpoint" }
}

# ---- VPC flow logs (security audit trail) -----------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.flow_logs_retention_days > 0 ? 1 : 0
  name              = "/${var.name_prefix}/vpc-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "flow_logs" {
  count = var.flow_logs_retention_days > 0 ? 1 : 0
  name  = "${var.name_prefix}-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.flow_logs_retention_days > 0 ? 1 : 0
  name  = "write-flow-logs"
  role  = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = var.flow_logs_retention_days > 0 ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "REJECT" # rejected traffic is the security signal; ALL is noisy and costly
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  tags            = { Name = "${var.name_prefix}-flow-log" }
}
