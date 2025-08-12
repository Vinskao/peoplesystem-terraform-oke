variable "lb_reserved_ip_display_name" {
  description = "Display name for the reserved public IP used by the Service LoadBalancer."
  type        = string
  default     = "service-lb-reserved-ip"
}

variable "dns_zone_name_or_id" {
  description = "OCI DNS zone OCID or zone name to create the A record in. Leave null to skip DNS record creation."
  type        = string
  default     = null
}

variable "service_fqdn" {
  description = "Fully qualified domain name for the Service LoadBalancer A record. Leave null to skip DNS record creation."
  type        = string
  default     = null
}

variable "dns_ttl" {
  description = "TTL for the DNS A record."
  type        = number
  default     = 300
}


