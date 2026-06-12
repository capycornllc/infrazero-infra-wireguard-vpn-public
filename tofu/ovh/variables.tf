variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "private_cidr" {
  type    = string
  default = "10.80.0.0/24"
}

variable "server_image_regex" {
  type        = string
  default     = "^Ubuntu 24\\.04"
  description = "Regex to match the OVH/OpenStack image name."
}

variable "egress_server_type" {
  type = string
}

variable "wg_listen_port" {
  type = number
}

variable "wg_server_address" {
  type = string
}

variable "wg_server_public_key" {
  type = string
}

variable "vpn_endpoint_mode" {
  type = string
}

variable "vpn_domain" {
  type    = string
  default = ""
}

variable "vpn_routing_mode" {
  type = string
}

variable "vpn_split_allowed_ips" {
  type    = string
  default = ""
}

variable "vpn_client_dns" {
  type    = string
  default = ""
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

variable "bootstrap_artifacts" {
  type = map(object({
    url    = string
    sha256 = string
  }))
}

variable "bootstrap_secrets" {
  type = object({
    url    = string
    sha256 = string
  })
  sensitive = true
}
