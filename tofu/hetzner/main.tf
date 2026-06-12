provider "hcloud" {
  token = var.hcloud_token
}

locals {
  labels = {
    project     = var.project
    environment = var.environment
    role        = "egress-vpn"
    managed_by  = "infrazero"
  }

  bootstrap = var.bootstrap_artifacts["egress-vpn"]
}

resource "hcloud_firewall" "vpn" {
  name = "${var.name_prefix}-vpn-fw"

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = tostring(var.wg_listen_port)
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "egress_vpn" {
  name        = "${var.name_prefix}-egress-vpn"
  image       = var.server_image
  server_type = var.egress_server_type
  location    = var.location
  labels      = local.labels

  firewall_ids = [hcloud_firewall.vpn.id]

  user_data = templatefile("${path.module}/templates/cloud-init.tftpl", {
    bootstrap_url                 = local.bootstrap.url
    bootstrap_sha256              = local.bootstrap.sha256
    bootstrap_secrets_url         = var.bootstrap_secrets.url
    bootstrap_secrets_sha256      = var.bootstrap_secrets.sha256
    wg_listen_port                = tostring(var.wg_listen_port)
    wg_server_address             = var.wg_server_address
    wg_server_public_key          = var.wg_server_public_key
  })
}
