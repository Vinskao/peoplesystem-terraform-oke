output "bucket_name" {
  description = "Bucket name."
  value       = oci_objectstorage_bucket.this.name
}

output "bucket_namespace" {
  description = "Object Storage namespace."
  value       = oci_objectstorage_bucket.this.namespace
}

output "bucket_access_type" {
  description = "Bucket access type."
  value       = oci_objectstorage_bucket.this.access_type
}

output "bucket_storage_tier" {
  description = "Bucket storage tier."
  value       = oci_objectstorage_bucket.this.storage_tier
}

output "tenancy_home_region" {
  description = "Home region discovered from the tenancy's region subscriptions (identity resources live here)."
  value       = local.discovered_home_region
}

output "bucket_versioning" {
  description = "Bucket versioning setting."
  value       = oci_objectstorage_bucket.this.versioning
}
