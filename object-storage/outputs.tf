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
