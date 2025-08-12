variable "compartment_id" {
  description = "Compartment OCID where the reserved public IP will be created"
  type        = string
}

variable "display_name" {
  description = "Display name for the reserved public IP"
  type        = string
  default     = "service-lb-reserved-ip"
}

