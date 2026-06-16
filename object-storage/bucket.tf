resource "oci_objectstorage_bucket" "this" {
  compartment_id        = var.compartment_id
  namespace             = local.objectstorage_namespace
  name                  = var.bucket_name
  access_type           = var.access_type
  storage_tier          = var.storage_tier
  versioning            = var.versioning
  auto_tiering          = var.auto_tiering
  kms_key_id            = var.kms_key_id
  object_events_enabled = var.object_events_enabled
  freeform_tags         = var.freeform_tags
  defined_tags          = var.defined_tags

  lifecycle {
    prevent_destroy = true
  }
}
