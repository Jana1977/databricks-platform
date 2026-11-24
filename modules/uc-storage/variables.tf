variable "name" {
  description = "Name prefix for the IAM role, storage credential and external location, for example dbx-int-cpps."
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket to create (globally unique)."
  type        = string
}

variable "aws_account_id" {
  type = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the IAM role."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroy to delete the bucket, credential and location even when they hold data. Test environments only."
  type        = bool
  default     = false
}

variable "versioning" {
  description = "Turn on S3 versioning for the bucket."
  type        = bool
  default     = true
}

variable "location_grants" {
  description = "Grants on the external location. A list (not a map) so principals that are not known until apply still work."
  type = list(object({
    principal  = string
    privileges = list(string)
  }))
  default = []
}

variable "comment" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
