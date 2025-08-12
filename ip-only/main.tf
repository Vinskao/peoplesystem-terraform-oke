resource "oci_core_public_ip" "reserved" {
  compartment_id = var.compartment_id
  display_name   = var.display_name
  lifetime       = "RESERVED"
}

output "reserved_public_ip_ocid" {
  value       = oci_core_public_ip.reserved.id
  description = "OCID of the reserved public IP"
}

output "reserved_public_ip_address" {
  value       = oci_core_public_ip.reserved.ip_address
  description = "IP address of the reserved public IP"
}

