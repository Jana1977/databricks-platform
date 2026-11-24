variable "name" {
  description = "Name prefix for every resource, for example dbx-int."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the new VPC, for example 10.20.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "private_subnet_cidrs" {
  description = "Subnets for Databricks compute, one per availability zone. Databricks needs at least 2, each between /17 and /26."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2 && alltrue([for c in var.private_subnet_cidrs : tonumber(split("/", c)[1]) >= 17 && tonumber(split("/", c)[1]) <= 26])
    error_message = "Give at least 2 private subnets, each between /17 and /26."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnets for the NAT gateways."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "Give at least 1 public subnet."
  }
}

variable "availability_zones" {
  description = "Availability zones to use. Empty = the first N available zones in the region."
  type        = list(string)
  default     = []
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways. 1 is cheapest (good for int); use one per AZ for availability."
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "nat_gateway_count must be at least 1."
  }
}

variable "enable_interface_endpoints" {
  description = "Create STS and Kinesis interface endpoints (costs money per hour, recommended for prod)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to flow_logs_bucket_arn."
  type        = bool
  default     = false
}

variable "flow_logs_bucket_arn" {
  description = "S3 bucket ARN for VPC flow logs (used when enable_flow_logs is true)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
