variable "environment" {
  description = "Environment to deploy (int or qa). Set by scripts/tf.sh as TF_VAR_environment."
  type        = string
}

variable "state_bucket" {
  description = "Terraform state bucket (reads stack 1 outputs). Set by scripts/tf.sh from TF_STATE_BUCKET."
  type        = string
}

variable "ci_client_id" {
  description = "Not used by this stack; accepted so every stack takes the same TF_VAR_ variables."
  type        = string
  default     = ""
}

variable "config_dir" {
  description = "Folder with <env>.yaml. Empty = config/ in this repo (only tests change this)."
  type        = string
  default     = ""
}

variable "teams_dir" {
  description = "Folder with <team>.yaml files. Empty = teams/ in this repo (only tests change this)."
  type        = string
  default     = ""
}
