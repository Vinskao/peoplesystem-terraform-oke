# Instance Principal authorization so the ty-multiverse-backend pods (running on OKE worker
# nodes) can READ objects in this bucket without any stored API keys.
#
# NOTE: OCI Identity (dynamic groups + policies) are global resources that must be created
# against the tenancy HOME region. If `var.region` is not your home region, run this with a
# provider pointed at the home region (or apply from the main root module that already targets it).
#
# Security scope: read-only, limited to this single bucket. The dynamic group matches worker-node
# instances by compartment; tighten with a tag-based matching rule if you need finer control.

variable "enable_instance_principal_read" {
  description = "Create the dynamic group + policy granting OKE instances read access to this bucket."
  type        = bool
  default     = true
}

variable "instance_principal_dynamic_group_name" {
  description = "Name of the dynamic group matching OKE worker-node instances."
  type        = string
  default     = "tymb-object-storage-readers"
}

variable "instance_principal_policy_name" {
  description = "Name of the policy granting read access to the bucket."
  type        = string
  default     = "tymb-object-storage-read-policy"
}

resource "oci_identity_dynamic_group" "object_storage_readers" {
  count          = var.enable_instance_principal_read ? 1 : 0
  compartment_id = var.compartment_id # dynamic groups live at the tenancy level
  name           = var.instance_principal_dynamic_group_name
  description    = "OKE worker-node instances allowed to read the ${var.bucket_name} bucket"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "object_storage_read" {
  count          = var.enable_instance_principal_read ? 1 : 0
  compartment_id = var.compartment_id
  name           = var.instance_principal_policy_name
  description    = "Read-only access to the ${var.bucket_name} bucket for ty-multiverse-backend"
  statements = [
    "Allow dynamic-group ${var.instance_principal_dynamic_group_name} to read objects in compartment id ${var.compartment_id} where target.bucket.name = '${var.bucket_name}'"
  ]

  depends_on = [oci_identity_dynamic_group.object_storage_readers]
}
