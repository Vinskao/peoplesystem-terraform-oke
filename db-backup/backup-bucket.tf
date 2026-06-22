data "oci_objectstorage_namespace" "this" {
  count          = var.namespace == null ? 1 : 0
  compartment_id = var.compartment_id
}

locals {
  namespace = coalesce(var.namespace, one(data.oci_objectstorage_namespace.this[*].namespace))
}

resource "oci_objectstorage_bucket" "db_backup" {
  compartment_id = var.compartment_id
  namespace      = local.namespace
  name           = var.backup_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Enabled" # guard against an overwritten/corrupt dump
  freeform_tags  = var.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Retention: archive old dumps, then delete them — no manual rotation needed.
resource "oci_objectstorage_object_lifecycle_policy" "retention" {
  bucket    = oci_objectstorage_bucket.db_backup.name
  namespace = local.namespace

  # The Object Storage service principal must be authorized before the lifecycle policy is accepted.
  depends_on = [oci_identity_policy.objectstorage_lifecycle]

  rules {
    name        = "archive-old-backups"
    action      = "ARCHIVE"
    time_amount = var.archive_after_days
    time_unit   = "DAYS"
    is_enabled  = true
    target      = "objects"
  }

  rules {
    name        = "delete-old-backups"
    action      = "DELETE"
    time_amount = var.delete_after_days
    time_unit   = "DAYS"
    is_enabled  = true
    target      = "objects"
  }
}
