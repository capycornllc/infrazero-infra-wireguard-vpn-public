# OVHcloud (OpenStack)-specific variable declarations.
# Common variables live in variables-common.tf (synced from tofu/common/).

variable "private_cidr" {
  type    = string
  default = "10.80.0.0/24"
}

variable "server_image_regex" {
  type        = string
  default     = "^Ubuntu 24\\.04"
  description = "Regex to match the OVH/OpenStack image name."
}

variable "ovh_application_key" {
  type      = string
  sensitive = true
}

variable "ovh_application_secret" {
  type      = string
  sensitive = true
}

variable "ovh_consumer_key" {
  type      = string
  sensitive = true
}

variable "ovh_cloud_project_id" {
  type = string
}

variable "openstack_auth_url" {
  type    = string
  default = "https://auth.cloud.ovh.net/v3"
}

variable "ovh_endpoint" {
  type    = string
  default = "ovh-eu"
}

variable "openstack_user_name" {
  type = string
}

variable "openstack_password" {
  type      = string
  sensitive = true
}

variable "ovh_ext_net_name" {
  type    = string
  default = "Ext-Net"
}
