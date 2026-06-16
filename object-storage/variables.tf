variable "oci_config_profile" {
  description = "OCI CLI config profile name."
  type        = string
  default     = "peoplesystem-v2"
}

variable "region" {
  description = "OCI region where the bucket will be created."
  type        = string
}

variable "compartment_id" {
  description = "OCI compartment OCID for the bucket."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique bucket name within the namespace."
  type        = string
}

variable "namespace" {
  description = "Object Storage namespace. Leave null to discover it from OCI."
  type        = string
  default     = null
}

variable "access_type" {
  description = "Bucket access type."
  type        = string
  default     = "NoPublicAccess"

  validation {
    condition     = contains(["NoPublicAccess", "ObjectRead", "ObjectReadWithoutList"], var.access_type)
    error_message = "access_type must be NoPublicAccess, ObjectRead, or ObjectReadWithoutList."
  }
}

variable "storage_tier" {
  description = "Bucket storage tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Archive"], var.storage_tier)
    error_message = "storage_tier must be Standard or Archive."
  }
}

variable "versioning" {
  description = "Bucket versioning setting."
  type        = string
  default     = "Disabled"

  validation {
    condition     = contains(["Enabled", "Suspended", "Disabled"], var.versioning)
    error_message = "versioning must be Enabled, Suspended, or Disabled."
  }
}

variable "auto_tiering" {
  description = "Whether OCI can automatically tier infrequently accessed objects."
  type        = string
  default     = "Disabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.auto_tiering)
    error_message = "auto_tiering must be Enabled or Disabled."
  }
}

variable "kms_key_id" {
  description = "Optional KMS key OCID for bucket encryption."
  type        = string
  default     = null
}

variable "object_events_enabled" {
  description = "Enable Object Events for this bucket."
  type        = bool
  default     = false
}

variable "freeform_tags" {
  description = "Freeform tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
