provider "oci" {
  config_file_profile = "peoplesystem-v2"
  region              = var.region
  auth                = "SecurityToken"
}

provider "oci" {
  config_file_profile = "peoplesystem-v2"
  region              = var.home_region
  alias               = "home"
  auth                = "SecurityToken"
}
