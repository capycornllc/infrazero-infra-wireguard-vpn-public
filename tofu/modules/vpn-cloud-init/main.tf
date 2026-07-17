# Shared cloud-init rendering for every VPN provider root.
# Provider roots keep only cloud resources and pass the same product contract here.

locals {
  bootstrap                   = var.bootstrap_artifacts["egress-vpn"]
  debug_root_password_escaped = replace(var.debug_root_password, "'", "'\"'\"'")

  cloud_init_rendered_egress_vpn = templatefile("${path.module}/templates/cloud-init.tftpl", {
    bootstrap_url               = local.bootstrap.url
    bootstrap_sha256            = local.bootstrap.sha256
    bootstrap_secrets_url       = var.bootstrap_secrets.url
    bootstrap_secrets_sha256    = var.bootstrap_secrets.sha256
    wg_listen_port              = tostring(var.wg_listen_port)
    wg_server_address           = var.wg_server_address
    wg_server_public_key        = var.wg_server_public_key
    admin_wg_listen_port        = tostring(var.admin_wg_listen_port)
    admin_wg_server_address     = var.admin_wg_server_address
    admin_users_json_b64        = var.admin_users_json_b64
    debug_root_password_escaped = local.debug_root_password_escaped
  })
}
