variable "admins_group_name" {
  description = "Account group that administers the workspace."
  type        = string
}

variable "token_max_lifetime_days" {
  description = "Longest lifetime a personal access token can have."
  type        = number
  default     = 90
}

variable "ip_allow_list" {
  description = "CIDRs allowed to reach the workspace. Empty = no IP access list. Include your GitHub runner egress IPs or CI will be locked out."
  type        = list(string)
  default     = []
}

variable "restrict_workspace_admins" {
  description = "Stop workspace admins from creating tokens for or running jobs as other identities."
  type        = bool
  default     = true
}

variable "disable_legacy_features" {
  description = "Turn off Hive metastore, DBFS root/mounts and no-isolation clusters (Unity Catalog only)."
  type        = bool
  default     = true
}
