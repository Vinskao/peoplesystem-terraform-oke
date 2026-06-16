data "oci_objectstorage_namespace" "this" {
  count          = var.namespace == null ? 1 : 0
  compartment_id = var.compartment_id
}

locals {
  objectstorage_namespace = coalesce(
    var.namespace,
    one(data.oci_objectstorage_namespace.this[*].namespace),
  )
}
