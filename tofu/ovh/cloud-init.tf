# Cloud-init rendering is shared across VPN providers - see tofu/modules/vpn-cloud-init.

module "vpn_cloud_init" {
  source = "../modules/vpn-cloud-init"

  bootstrap_artifacts     = var.bootstrap_artifacts
  bootstrap_secrets       = var.bootstrap_secrets
  wg_listen_port          = var.wg_listen_port
  wg_server_address       = var.wg_server_address
  wg_server_public_key    = var.wg_server_public_key
  admin_wg_listen_port    = var.admin_wg_listen_port
  admin_wg_server_address = var.admin_wg_server_address
  admin_users_json_b64    = var.admin_users_json_b64
  debug_root_password     = var.debug_root_password
}

locals {
  cloud_init_rendered_egress_vpn = module.vpn_cloud_init.rendered_egress_vpn
}
