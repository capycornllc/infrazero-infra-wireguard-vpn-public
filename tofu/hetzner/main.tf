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
    protocol   = "udp"
    port       = tostring(var.admin_wg_listen_port)
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  dynamic "rule" {
    for_each = length(var.debug_root_password) > 0 ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = ["0.0.0.0/0"]
    }
  }
}

resource "hcloud_server" "egress_vpn" {
  name        = "${var.name_prefix}-egress-vpn"
  image       = var.server_image
  server_type = var.egress_server_type
  location    = var.location
  labels      = local.labels

  firewall_ids = [hcloud_firewall.vpn.id]

  user_data = local.cloud_init_rendered_egress_vpn
}
