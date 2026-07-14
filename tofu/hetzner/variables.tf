variable "hcloud_token" {
  type      = string
  sensitive = true
}

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

variable "server_image" {
  type = string
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

variable "admin_wg_listen_port" {
  type    = number
  default = 51821
}

variable "admin_wg_server_address" {
  type    = string
  default = "10.81.0.1/24"
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

variable "admin_users_json_b64" {
  type        = string
  description = "Base64-encoded JSON array of admin users with SSH public keys."
}

variable "debug_root_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Emergency root password for debug SSH access. Leave empty in production. When set, enables password auth and opens SSH port to the internet."
}
