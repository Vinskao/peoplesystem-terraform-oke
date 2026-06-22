variable "oci_config_profile" {
  description = "OCI CLI config profile name."
  type        = string
  default     = "peoplesystem-v2"
}

variable "region" {
  description = "OCI region."
  type        = string
  default     = "ap-singapore-2"
}

variable "compartment_id" {
  description = "OCI compartment OCID (also the dynamic-group/policy compartment)."
  type        = string
}

variable "namespace" {
  description = "Object Storage namespace. Leave null to auto-discover."
  type        = string
  default     = null
}

variable "backup_bucket_name" {
  description = "Globally-unique bucket name for database backups."
  type        = string
  default     = "peoplesystem-db-backup"
}

variable "archive_after_days" {
  description = "Move backups to the Archive tier after this many days."
  type        = number
  default     = 7
}

variable "delete_after_days" {
  description = "Delete backups after this many days (retention)."
  type        = number
  default     = 30
}

variable "enable_instance_principal_write" {
  description = "Create the dynamic group + policy letting OKE nodes (the backup CronJob) write to the bucket."
  type        = bool
  default     = true
}

variable "dynamic_group_name" {
  description = "Dynamic group name for backup writers (OKE worker-node instances)."
  type        = string
  default     = "peoplesystem-db-backup-writers"
}

variable "policy_name" {
  description = "Policy name granting object write to the backup bucket."
  type        = string
  default     = "peoplesystem-db-backup-write"
}

variable "freeform_tags" {
  description = "Freeform tags."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "peoplesystem"
    purpose    = "db-backup"
  }
}
