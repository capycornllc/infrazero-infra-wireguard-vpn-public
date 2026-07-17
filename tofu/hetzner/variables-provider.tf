# Hetzner-specific variable declarations.
# Common variables live in variables-common.tf (synced from tofu/common/).

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_image" {
  type    = string
  default = "ubuntu-22.04"
}
