# VPC for the Databricks classic compute plane (customer-managed VPC).
#
# Layout:
#   public subnets   -> internet gateway, NAT gateways
#   private subnets  -> Databricks clusters and SQL warehouses (one per AZ, at least 2)
#   S3 gateway endpoint on the private route tables (free, keeps S3 traffic off NAT)
#   optional STS and Kinesis interface endpoints
#   optional VPC flow logs to an S3 bucket

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, length(var.private_subnet_cidrs))

  # Ports Databricks needs from the compute plane to the control plane and AWS services.
  # https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc
  egress_ports = {
    https       = { from = 443, to = 443 }
    fips        = { from = 2443, to = 2443 }
    metastore   = { from = 3306, to = 3306 }
    scc_relay   = { from = 6666, to = 6666 }
    internal_cp = { from = 8443, to = 8451 }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name })
}

# ---------- public side ----------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index % length(local.azs)]
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.name}-public-${count.index}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

# ---------- private side (Databricks compute) ----------

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = merge(var.tags, { Name = "${var.name}-compute-${count.index}" })
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-compute-${count.index}" })
}

resource "aws_route" "private_nat" {
  count                  = length(aws_route_table.private)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index % var.nat_gateway_count].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group shared by every cluster node.
resource "aws_security_group" "workspace" {
  name        = "${var.name}-workspace"
  description = "Databricks classic compute nodes"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name}-workspace" })
}

resource "aws_vpc_security_group_ingress_rule" "self" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "-1"
  description                  = "All traffic between cluster nodes"
}

resource "aws_vpc_security_group_egress_rule" "self" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "-1"
  description                  = "All traffic between cluster nodes"
}

resource "aws_vpc_security_group_egress_rule" "databricks" {
  for_each          = local.egress_ports
  security_group_id = aws_security_group.workspace.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.from
  to_port           = each.value.to
  description       = "Databricks ${each.key}"
}

# ---------- VPC endpoints ----------

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "endpoints" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${var.name}-aws-endpoints"
  description = "AWS interface endpoints (STS, Kinesis)"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name}-aws-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count                        = var.enable_interface_endpoints ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from cluster nodes"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.enable_interface_endpoints ? toset(["sts", "kinesis-streams"]) : toset([])
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# ---------- flow logs ----------

resource "aws_flow_log" "this" {
  count                = var.enable_flow_logs ? 1 : 0
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = var.flow_logs_bucket_arn
  tags                 = merge(var.tags, { Name = "${var.name}-flow-logs" })
}
