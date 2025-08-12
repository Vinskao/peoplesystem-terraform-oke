locals {
  ingress_annotations = merge({
    "service.beta.kubernetes.io/oci-load-balancer-ip-mode"     = "reserved",
    "service.beta.kubernetes.io/oci-load-balancer-reserved-ip" = oci_core_public_ip.service_lb_reserved.id,
  }, var.ingress_nginx_additional_annotations)
}

resource "kubernetes_namespace_v1" "ingress_nginx" {
  count = var.create_ingress_controller ? 1 : 0
  metadata {
    name = var.ingress_nginx_namespace
  }
}

resource "helm_release" "ingress_nginx" {
  count            = var.create_ingress_controller ? 1 : 0
  name             = "ingress-nginx"
  namespace        = var.ingress_nginx_namespace
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  create_namespace = false

  # 讓 Controller Service 走我們的保留 IP（以 values 傳遞，提升兼容性）
  values = [yamlencode({
    controller = {
      service = {
        annotations = local.ingress_annotations
      }
    }
  })]

  depends_on = [
    kubernetes_namespace_v1.ingress_nginx,
  ]
}


