# Toggle: create or skip reserved public IP for service LB
variable "create_lb_reserved_ip" {
  description = "Whether to create a reserved public IP for the service LoadBalancer."
  type        = bool
  default     = true
}

resource "oci_core_public_ip" "service_lb_reserved" {
  count = var.create_lb_reserved_ip ? 1 : 0
  # Safe during destroy: do not depend on network/module outputs
  compartment_id = coalesce(var.network_compartment_id, local.compartment_id)

  display_name = var.lb_reserved_ip_display_name
  lifetime     = "RESERVED"

  freeform_tags = try(local.network_freeform_tags, {})
  defined_tags  = try(local.network_defined_tags, {})
}

output "service_lb_reserved_ip_ocid" {
  description = "OCID of the reserved public IP for the service LoadBalancer."
  value       = try(one(oci_core_public_ip.service_lb_reserved[*].id), null)
}

output "service_lb_reserved_ip_address" {
  description = "IP address of the reserved public IP for the service LoadBalancer."
  value       = try(one(oci_core_public_ip.service_lb_reserved[*].ip_address), null)
}

# Optional DNS rrset for A record pointing to reserved IP
resource "oci_dns_rrset" "service_a" {
  count            = (var.dns_zone_name_or_id != null && var.service_fqdn != null && var.create_lb_reserved_ip) ? 1 : 0
  zone_name_or_id  = var.dns_zone_name_or_id
  domain           = var.service_fqdn
  rtype            = "A"
  compartment_id   = local.compartment_id

  items {
    domain = var.service_fqdn
    rdata  = one(oci_core_public_ip.service_lb_reserved[*].ip_address)
    rtype  = "A"
    ttl    = var.dns_ttl
  }
}


