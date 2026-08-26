# Instance Principal authorization so the ty-multiverse-backend / maya-sawa pods (running on
# OKE worker nodes) can access this bucket without any stored API keys.
#
# IMPORTANT: OCI Identity (dynamic groups + policies) are GLOBAL resources that must be created
# against the tenancy HOME region. The bucket lives in var.region (ap-singapore-2) but identity
# must go through the `oci.home` provider alias below.
#
# Permission scope (research-zone publish pipeline):
#   - read the current mapping object          -> OBJECT_READ / OBJECT_INSPECT
#   - write a new version                      -> OBJECT_CREATE / OBJECT_OVERWRITE
#   - read it back for hash verification       -> OBJECT_READ
#   - write backup + metadata objects          -> OBJECT_CREATE
#   - NO delete                                -> OBJECT_DELETE / OBJECT_VERSION_DELETE withheld
#
# With bucket versioning Enabled, an overwrite keeps the previous version, so rollback never
# requires delete permission.

variable "home_region" {
  description = <<-EOT
    Tenancy home region. Identity resources (dynamic groups, policies) must be created here.
    This value is NOT trusted blindly: the precondition below verifies it against the tenancy's
    actual region subscriptions at plan time, so a wrong value fails loudly instead of silently
    creating identity resources in the wrong region.
  EOT
  type        = string
  default     = "ap-singapore-2" # verified: tenancy home region key XSP
}

variable "enable_instance_principal_access" {
  description = "Create the dynamic group + policy granting OKE instances access to this bucket."
  type        = bool
  default     = true
}

variable "instance_principal_dynamic_group_name" {
  description = "Name of the dynamic group matching OKE worker-node instances."
  type        = string
  default     = "tymb-object-storage-readers"
}

variable "instance_principal_policy_name" {
  description = "Name of the policy granting bucket access."
  type        = string
  default     = "tymb-object-storage-read-policy"
}

variable "preflight_prefix" {
  description = "Object name prefix used by the connectivity preflight; cleaned up by lifecycle rule."
  type        = string
  default     = "_preflight/"
}

provider "oci" {
  alias               = "home"
  config_file_profile = var.oci_config_profile
  region              = var.home_region
  auth                = "SecurityToken"
}

# Authoritative source for the tenancy home region — never inferred from the CLI profile.
data "oci_identity_region_subscriptions" "this" {
  tenancy_id = var.compartment_id
}

locals {
  discovered_home_region = one([
    for subscription in data.oci_identity_region_subscriptions.this.region_subscriptions :
    subscription.region_name if subscription.is_home_region
  ])
}

resource "oci_identity_dynamic_group" "object_storage_readers" {
  count          = var.enable_instance_principal_access ? 1 : 0
  provider       = oci.home
  compartment_id = var.compartment_id # dynamic groups live at the tenancy level
  name           = var.instance_principal_dynamic_group_name
  description    = "OKE worker-node instances allowed to access the ${var.bucket_name} bucket"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}'}"

  lifecycle {
    precondition {
      condition = var.home_region == local.discovered_home_region
      error_message = format(
        "home_region is set to %q but this tenancy's home region is %q. Identity resources are global and must be created in the home region.",
        var.home_region,
        local.discovered_home_region,
      )
    }
  }
}

resource "oci_identity_policy" "object_storage_access" {
  count          = var.enable_instance_principal_access ? 1 : 0
  provider       = oci.home
  compartment_id = var.compartment_id
  name           = var.instance_principal_policy_name
  description    = "Read + write-new-version access (no delete) to ${var.bucket_name} for ty-multiverse workloads"

  statements = [
    # Needed for HeadBucket / listing object versions during read-back verification.
    "Allow dynamic-group ${var.instance_principal_dynamic_group_name} to inspect buckets in compartment id ${var.compartment_id} where target.bucket.name = '${var.bucket_name}'",

    # Read the current mapping, backups and metadata.
    "Allow dynamic-group ${var.instance_principal_dynamic_group_name} to read objects in compartment id ${var.compartment_id} where target.bucket.name = '${var.bucket_name}'",

    # Write new versions / backups / metadata. Deliberately enumerates permissions so that
    # OBJECT_DELETE and OBJECT_VERSION_DELETE are NOT granted.
    <<-EOT
    Allow dynamic-group ${var.instance_principal_dynamic_group_name} to manage objects in compartment id ${var.compartment_id} where all {
      target.bucket.name = '${var.bucket_name}',
      any {
        request.permission = 'OBJECT_CREATE',
        request.permission = 'OBJECT_OVERWRITE',
        request.permission = 'OBJECT_INSPECT',
        request.permission = 'OBJECT_READ'
      }
    }
    EOT
    ,

    # Object Storage lifecycle rules are executed by the Object Storage SERVICE principal, not by
    # our workload. Without this grant PutObjectLifecyclePolicy fails with
    # 400-InsufficientServicePermissions. Scoped to this bucket only.
    #
    # This is what actually deletes the _preflight/ probes: the service can delete here, the
    # workload still cannot.
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_id} where target.bucket.name = '${var.bucket_name}'",
  ]

  depends_on = [oci_identity_dynamic_group.object_storage_readers]
}
