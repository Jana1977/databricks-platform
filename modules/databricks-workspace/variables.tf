variable "name" {
  description = "Name prefix for AWS and Databricks objects, for example dbx-int."
  type        = string
}

variable "workspace_name" {
  description = "Workspace name shown in the account console."
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account that hosts the workspace."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for cluster nodes (at least 2 AZs)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for cluster nodes."
  type        = string
}

variable "private_link" {
  description = "Back-end PrivateLink IDs. null = no PrivateLink."
  type = object({
    rest_vpc_endpoint_id       = string
    relay_vpc_endpoint_id      = string
    private_access_settings_id = string
  })
  default = null
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary set on every IAM role this module creates."
  type        = string
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the root bucket with its data. Use true only in test environments."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
