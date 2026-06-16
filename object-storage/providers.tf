provider "oci" {
  config_file_profile = var.oci_config_profile
  region              = var.region
  auth                = "SecurityToken"
}
