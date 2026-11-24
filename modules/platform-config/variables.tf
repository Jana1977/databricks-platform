variable "environment" {
  description = "Environment being deployed (int, qa, ...). Selects config/<environment>.yaml."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lower-case letters/digits, for example int or qa."
  }
}

variable "config_raw" {
  description = "config/<environment>.yaml as decoded YAML (used to catch misspelled keys)."
  type        = any
}

variable "config" {
  description = "Same file, typed. Every optional key gets its default here."
  type = object({
    environment = string
    name_prefix = optional(string, "dbx")

    aws = object({
      account_id = string
      region     = string
    })

    databricks = object({
      account_id     = string
      workspace_name = optional(string, "")
      admins         = list(string)
      create_users   = optional(bool, false)
    })

    unity_catalog = optional(object({
      metastore_id     = optional(string, "")
      create_metastore = optional(bool, false)
      assign_metastore = optional(bool, true)
      platform_catalog = optional(bool, true)
    }), {})

    network = object({
      vpc_cidr             = string
      private_subnet_cidrs = list(string)
      public_subnet_cidrs  = list(string)
      availability_zones   = optional(list(string), [])
      nat_gateway_count    = optional(number, 1)
      interface_endpoints  = optional(bool, false)
      flow_logs            = optional(bool, false)

      privatelink = optional(object({
        enabled               = optional(bool, false)
        subnet_cidrs          = optional(list(string), [])
        public_access_enabled = optional(bool, true)
        workspace_service     = optional(string, "")
        relay_service         = optional(string, "")
        frontend = optional(object({
          vpc_id        = optional(string, "")
          subnet_ids    = optional(list(string), [])
          allowed_cidrs = optional(list(string), [])
        }), {})
      }), {})
    })

    workspace = optional(object({
      token_max_lifetime_days   = optional(number, 90)
      ip_allow_list             = optional(list(string), [])
      restrict_workspace_admins = optional(bool, true)
      disable_legacy_features   = optional(bool, true)
    }), {})

    safety = optional(object({
      allow_destroy_data = optional(bool, false)
    }), {})

    tags = optional(map(string), {})
  })
}

variable "teams_dir" {
  description = "Folder with one <team>.yaml per team. Files starting with _ are ignored."
  type        = string
}
