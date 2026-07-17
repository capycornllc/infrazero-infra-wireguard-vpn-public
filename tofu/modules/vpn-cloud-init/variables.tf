# Inputs for the shared VPN cloud-init rendering module.

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
  type = number
}

variable "admin_wg_server_address" {
  type = string
}

variable "admin_users_json_b64" {
  type = string
}

variable "debug_root_password" {
  type      = string
  sensitive = true
}
