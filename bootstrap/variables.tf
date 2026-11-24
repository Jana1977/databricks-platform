variable "environment" {
  description = "Environment this bootstrap is for: int or qa."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lower-case letters/digits."
  }
}

variable "name_prefix" {
  description = "Same value as name_prefix in config/<env>.yaml."
  type        = string
  default     = "dbx"
}

variable "aws_region" {
  description = "Region for the state bucket. Same as aws.region in config/<env>.yaml."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the platform repo (exact case)."
  type        = string
}

variable "github_repo" {
  description = "Name of the platform repo in GitHub."
  type        = string
  default     = "databricks-platform"
}

variable "create_github_oidc_provider" {
  description = "false if this AWS account already has the token.actions.githubusercontent.com identity provider (for example, when int and qa share an account and int created it)."
  type        = bool
  default     = true
}
