variable "team" {
  description = "One team, as read from teams/<team>.yaml. See teams/_template.yaml for every key."
  type = object({
    name               = string
    description        = optional(string, "")
    environments       = optional(list(string), [])
    managers           = list(string)
    members            = optional(list(string), [])
    groups             = optional(map(list(string)), {})
    service_principals = optional(list(string), [])
    job_repos          = optional(list(string), [])

    compute = optional(object({
      node_types              = optional(list(string), ["m5d.large", "m5d.xlarge"])
      max_workers             = optional(number, 4)
      allow_interactive       = optional(bool, true)
      autotermination_minutes = optional(number, 30)
      max_clusters_per_user   = optional(number, 2)
    }), {})

    sql_warehouse = optional(object({
      enabled           = optional(bool, true)
      size              = optional(string, "2X-Small")
      auto_stop_minutes = optional(number, 10)
      max_clusters      = optional(number, 1)
      serverless        = optional(bool, false)
    }), {})

    catalog = optional(object({
      schemas = optional(list(string), ["raw", "curated"])
    }), {})

    secret_scope = optional(bool, true)

    budget = optional(object({
      monthly_usd  = optional(number, 0)
      alert_emails = optional(list(string), [])
    }), {})
  })

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,19}$", var.team.name)) && !contains(["platform", "admins", "users", "account"], var.team.name)
    error_message = "team.name must be 2-20 lower-case letters/digits, start with a letter, and not be platform, admins, users or account."
  }

  validation {
    condition     = length(var.team.managers) > 0 && alltrue([for e in concat(var.team.managers, var.team.members, flatten(values(var.team.groups))) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "team.managers needs at least 1 entry, and managers/members/groups must be e-mail addresses."
  }

  validation {
    condition     = alltrue([for g in keys(var.team.groups) : can(regex("^[a-z][a-z0-9-]{1,30}$", g)) && !contains(["users", "managers"], g)])
    error_message = "team.groups keys must be lower-case (a-z, 0-9, -), 2-31 chars, and not 'users' or 'managers'."
  }

  validation {
    condition     = alltrue([for s in var.team.service_principals : can(regex("^[a-z][a-z0-9-]{1,30}$", s)) && s != "deploy"])
    error_message = "team.service_principals entries must be lower-case (a-z, 0-9, -) and not 'deploy' (the deploy service principal is always created)."
  }

  validation {
    condition     = alltrue([for r in var.team.job_repos : can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", r))])
    error_message = "team.job_repos entries must look like <github-org>/<repo>."
  }

  validation {
    condition     = length(var.team.compute.node_types) > 0 && var.team.compute.max_workers >= 1
    error_message = "team.compute.node_types needs at least 1 instance type and max_workers must be >= 1."
  }

  validation {
    condition     = contains(["2X-Small", "X-Small", "Small", "Medium", "Large", "X-Large", "2X-Large", "3X-Large", "4X-Large"], var.team.sql_warehouse.size)
    error_message = "team.sql_warehouse.size must be one of 2X-Small, X-Small, Small, Medium, Large, X-Large, 2X-Large, 3X-Large, 4X-Large."
  }

  validation {
    condition     = alltrue([for s in var.team.catalog.schemas : can(regex("^[a-z][a-z0-9_]{0,62}$", s))])
    error_message = "team.catalog.schemas must be lower-case names (a-z, 0-9, _)."
  }
}

variable "environment" {
  description = "Environment name (int, qa, ...)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used in AWS and account-level names, for example dbx."
  type        = string
}

variable "aws_account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "workspace_id" {
  description = "Numeric workspace ID."
  type        = string
}

variable "workspace_url" {
  description = "https:// URL of the workspace."
  type        = string
}

variable "admins_group_name" {
  description = "Platform admins group; gets full access to every team object for support."
  type        = string
}

variable "teams_folder" {
  description = "Parent workspace folder for team folders."
  type        = string
  default     = "/Teams"
}

variable "state_bucket" {
  description = "Terraform state bucket. The team's job repo CI role may use the jobs/<env>/<team>/ prefix only."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider in this AWS account."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary set on every IAM role."
  type        = string
}

variable "create_users" {
  description = "true = create missing users in the Databricks account (sandbox accounts without identity sync). false = users must already exist."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow destroy to delete the team catalog, bucket and folder with their data. Test environments only."
  type        = bool
  default     = false
}

variable "secret_lifetime_days" {
  description = "Lifetime of the deploy service principal's OAuth secret."
  type        = number
  default     = 180
}

variable "secret_rotation_days" {
  description = "Terraform replaces the OAuth secret on the first apply after this many days. Must be shorter than secret_lifetime_days."
  type        = number
  default     = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
