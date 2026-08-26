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

    # OCI stamps Oracle-Tags.CreatedBy / CreatedOn on the bucket automatically. Terraform would
    # otherwise try to strip them on every apply and OCI would re-add them — permanent drift with
    # no functional effect. Bucket settings (name, versioning, access_type) are still enforced.
    ignore_changes = [defined_tags]
  }
}

# Preflight objects are written by the connectivity check and must not accumulate.
# The workload principal has no delete permission, so cleanup is done by a lifecycle rule
# rather than by the pipeline itself.
resource "oci_objectstorage_object_lifecycle_policy" "preflight_cleanup" {
  namespace = local.objectstorage_namespace
  bucket    = oci_objectstorage_bucket.this.name

  rules {
    name        = "delete-preflight-objects"
    action      = "DELETE"
    time_amount = 1
    time_unit   = "DAYS"
    is_enabled  = true

    object_name_filter {
      inclusion_prefixes = [var.preflight_prefix]
    }
  }
}
