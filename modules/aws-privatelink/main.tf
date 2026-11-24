# AWS PrivateLink for Databricks (needs the Enterprise tier).
#
# Back-end (always, when this module is used):
#   cluster nodes -> REST API endpoint + secure cluster connectivity (SCC) relay endpoint,
#   both in dedicated subnets of the workspace VPC, registered with the Databricks account.
#
# Front-end (optional):
#   users -> REST API endpoint in a separate "transit" VPC that your corporate network reaches.
#   You still need DNS in your corporate network that points the workspace URL at that endpoint.

locals {
  # Databricks endpoint services per region.
  # Source: https://docs.databricks.com/aws/en/resources/ip-domain-region (PrivateLink VPC endpoint services)
  services = {
    "us-east-1" = { workspace = "com.amazonaws.vpce.us-east-1.vpce-svc-09143d1e626de2f04", relay = "com.amazonaws.vpce.us-east-1.vpce-svc-00018a8c3ff62ffdf" }
    "us-east-2" = { workspace = "com.amazonaws.vpce.us-east-2.vpce-svc-041dc2b4d7796b8d3", relay = "com.amazonaws.vpce.us-east-2.vpce-svc-090a8fab0d73e39a6" }
    "us-west-2" = { workspace = "com.amazonaws.vpce.us-west-2.vpce-svc-0129f463fcfbc46c5", relay = "com.amazonaws.vpce.us-west-2.vpce-svc-0158114c0c730c3bb" }
  }

  workspace_service = var.workspace_service_name != "" ? var.workspace_service_name : try(local.services[var.region].workspace, "")
  relay_service     = var.relay_service_name != "" ? var.relay_service_name : try(local.services[var.region].relay, "")

  # Ports from cluster nodes to the endpoints.
  ports = {
    https       = { from = 443, to = 443 }
    fips        = { from = 2443, to = 2443 }
    scc_relay   = { from = 6666, to = 6666 }
    internal_cp = { from = 8443, to = 8451 }
  }

  frontend = var.frontend.vpc_id != ""
}

resource "terraform_data" "service_names" {
  lifecycle {
    precondition {
      condition     = local.workspace_service != "" && local.relay_service != ""
      error_message = "No PrivateLink endpoint service names known for region ${var.region}. Set network.privatelink.workspace_service and relay_service in the config file (see the Databricks 'IP addresses and domains' page)."
    }
  }
}

# ---------- back-end ----------

resource "aws_subnet" "endpoints" {
  count             = length(var.subnet_cidrs)
  vpc_id            = var.vpc_id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]
  tags              = merge(var.tags, { Name = "${var.name}-privatelink-${count.index}" })
}

resource "aws_route_table" "endpoints" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.name}-privatelink" })
}

resource "aws_route_table_association" "endpoints" {
  count          = length(aws_subnet.endpoints)
  subnet_id      = aws_subnet.endpoints[count.index].id
  route_table_id = aws_route_table.endpoints.id
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-privatelink"
  description = "Databricks PrivateLink endpoints"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-privatelink" })
}

resource "aws_vpc_security_group_ingress_rule" "from_compute" {
  for_each                     = local.ports
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = var.compute_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  description                  = "From cluster nodes (${each.key})"
}

resource "aws_vpc_security_group_egress_rule" "to_compute" {
  for_each                     = local.ports
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = var.compute_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  description                  = "To cluster nodes (${each.key})"
}

resource "aws_vpc_endpoint" "rest" {
  vpc_id              = var.vpc_id
  service_name        = local.workspace_service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoints[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-databricks-rest" })

  depends_on = [terraform_data.service_names]
}

resource "aws_vpc_endpoint" "relay" {
  vpc_id              = var.vpc_id
  service_name        = local.relay_service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.endpoints[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-databricks-relay" })

  depends_on = [terraform_data.service_names]
}

resource "databricks_mws_vpc_endpoint" "rest" {
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = aws_vpc_endpoint.rest.id
  vpc_endpoint_name   = "${var.name}-rest"
  region              = var.region
}

resource "databricks_mws_vpc_endpoint" "relay" {
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = aws_vpc_endpoint.relay.id
  vpc_endpoint_name   = "${var.name}-relay"
  region              = var.region
}

# ---------- front-end (optional) ----------

resource "aws_security_group" "frontend" {
  count       = local.frontend ? 1 : 0
  name        = "${var.name}-privatelink-frontend"
  description = "Databricks front-end PrivateLink endpoint"
  vpc_id      = var.frontend.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-privatelink-frontend" })
}

resource "aws_vpc_security_group_ingress_rule" "frontend_https" {
  for_each          = local.frontend ? toset(var.frontend.allowed_cidrs) : toset([])
  security_group_id = aws_security_group.frontend[0].id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from users"
}

resource "aws_vpc_endpoint" "frontend" {
  count               = local.frontend ? 1 : 0
  vpc_id              = var.frontend.vpc_id
  service_name        = local.workspace_service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.frontend.subnet_ids
  security_group_ids  = [aws_security_group.frontend[0].id]
  private_dns_enabled = false
  tags                = merge(var.tags, { Name = "${var.name}-databricks-frontend" })

  depends_on = [terraform_data.service_names]
}

resource "databricks_mws_vpc_endpoint" "frontend" {
  count               = local.frontend ? 1 : 0
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = aws_vpc_endpoint.frontend[0].id
  vpc_endpoint_name   = "${var.name}-frontend"
  region              = var.region
}

# ---------- private access settings ----------

resource "databricks_mws_private_access_settings" "this" {
  account_id                   = var.databricks_account_id
  private_access_settings_name = "${var.name}-pas"
  region                       = var.region
  public_access_enabled        = var.public_access_enabled
  private_access_level         = "ACCOUNT"
}
