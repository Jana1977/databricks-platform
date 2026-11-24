variable "name" {
  description = "Name prefix, for example dbx-int."
  type        = string
}

variable "region" {
  description = "AWS region of the workspace."
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID."
  type        = string
}

variable "vpc_id" {
  description = "Workspace VPC."
  type        = string
}

variable "availability_zones" {
  description = "Zones for the endpoint subnets."
  type        = list(string)
}

variable "subnet_cidrs" {
  description = "Small subnets (for example /27) for the back-end endpoints, inside the VPC CIDR."
  type        = list(string)

  validation {
    condition     = length(var.subnet_cidrs) >= 1
    error_message = "Give at least 1 endpoint subnet."
  }
}

variable "compute_security_group_id" {
  description = "Security group of the cluster nodes."
  type        = string
}

variable "workspace_service_name" {
  description = "Override for the 'General Access (REST API)' endpoint service. Empty = built-in value for the region."
  type        = string
  default     = ""
}

variable "relay_service_name" {
  description = "Override for the 'Secure cluster connectivity relay' endpoint service. Empty = built-in value for the region."
  type        = string
  default     = ""
}

variable "public_access_enabled" {
  description = "true = users can still reach the workspace over the internet. false = only through a front-end endpoint."
  type        = bool
  default     = true
}

variable "frontend" {
  description = "Optional front-end endpoint in a transit VPC. Leave vpc_id empty to skip."
  type = object({
    vpc_id        = optional(string, "")
    subnet_ids    = optional(list(string), [])
    allowed_cidrs = optional(list(string), [])
  })
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
