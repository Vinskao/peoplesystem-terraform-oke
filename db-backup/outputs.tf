output "backup_bucket_name" {
  description = "Name of the DB backup bucket."
  value       = oci_objectstorage_bucket.db_backup.name
}

output "backup_bucket_namespace" {
  description = "Object Storage namespace."
  value       = local.namespace
}

output "dynamic_group_name" {
  description = "Dynamic group granted write access (empty if disabled)."
  value       = var.enable_instance_principal_write ? var.dynamic_group_name : null
}
