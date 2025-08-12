variable "create_ingress_controller" {
  description = "Whether to install ingress-nginx via Helm."
  type        = bool
  default     = false
}

variable "ingress_nginx_namespace" {
  description = "Namespace to install ingress-nginx."
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_chart_version" {
  description = "Optional chart version for ingress-nginx Helm chart. If null, latest will be used."
  type        = string
  default     = null
}

variable "ingress_nginx_additional_annotations" {
  description = "Additional annotations to add to the ingress-nginx LoadBalancer Service."
  type        = map(string)
  default     = {}
}


