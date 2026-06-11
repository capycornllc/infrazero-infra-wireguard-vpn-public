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

variable "wg_server_private_key" {
  type      = string
  sensitive = true
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

variable "vpn_peers_json" {
  type      = string
  sensitive = true
}

variable "bootstrap_artifacts" {
  type = map(object({
    url    = string
    sha256 = string
  }))
}
