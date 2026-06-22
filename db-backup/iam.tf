# Instance Principal authorization so the backup CronJob (running on an OKE worker node) can
# WRITE dump objects to the backup bucket — no stored OCI keys.
#
# NOTE: OCI Identity resources are global and must be created against the tenancy HOME region.

resource "oci_identity_dynamic_group" "backup_writers" {
  count          = var.enable_instance_principal_write ? 1 : 0
  compartment_id = var.compartment_id # dynamic groups live at the tenancy level
  name           = var.dynamic_group_name
  description    = "OKE worker-node instances allowed to write DB backups to ${var.backup_bucket_name}"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "backup_write" {
  count          = var.enable_instance_principal_write ? 1 : 0
  compartment_id = var.compartment_id
  name           = var.policy_name
  description    = "Allow the backup CronJob to write objects to ${var.backup_bucket_name}"
  statements = [
    # manage objects = read + write + delete within the single backup bucket only
    "Allow dynamic-group ${var.dynamic_group_name} to manage objects in compartment id ${var.compartment_id} where target.bucket.name = '${var.backup_bucket_name}'"
  ]

  depends_on = [oci_identity_dynamic_group.backup_writers]
}

# Object lifecycle (archive/delete) is performed by the Object Storage service principal on your
# behalf, so it must be authorized to manage objects in the backup bucket — otherwise
# PutObjectLifecyclePolicy fails with 400-InsufficientServicePermissions.
resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.compartment_id
  name           = "${var.policy_name}-lifecycle"
  description    = "Allow Object Storage service to run lifecycle on ${var.backup_bucket_name}"
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_id} where target.bucket.name = '${var.backup_bucket_name}'"
  ]
}
