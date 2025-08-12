provider "oci" {
  config_file_profile = "peoplesystem-v2"
  region              = var.region
  auth                = "SecurityToken"
}

provider "oci" {
  config_file_profile = "peoplesystem-v2"
  region              = var.region
  alias               = "home"
  auth                = "SecurityToken"
}

# Kubernetes provider expects local kubeconfig to be configured already
provider "kubernetes" {}
