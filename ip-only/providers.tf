variable "region" { type = string }
variable "profile" { type = string }

provider "oci" {
  region              = var.region
  config_file_profile = var.profile
  auth                = "SecurityToken"
}

