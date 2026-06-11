output "egress_public_ipv4" {
  value = hcloud_server.egress_vpn.ipv4_address
}

output "egress_server_id" {
  value = hcloud_server.egress_vpn.id
}

output "wireguard_listen_port" {
  value = var.wg_listen_port
}

output "wireguard_public_ip_endpoint" {
  value = "${hcloud_server.egress_vpn.ipv4_address}:${var.wg_listen_port}"
}

output "wireguard_domain_endpoint" {
  value = var.vpn_endpoint_mode == "domain" && trimspace(var.vpn_domain) != "" ? "${var.vpn_domain}:${var.wg_listen_port}" : ""
}

output "wireguard_endpoint" {
  value = var.vpn_endpoint_mode == "domain" && trimspace(var.vpn_domain) != "" ? "${var.vpn_domain}:${var.wg_listen_port}" : "${hcloud_server.egress_vpn.ipv4_address}:${var.wg_listen_port}"
}
