output "egress_public_ipv4" {
  value = openstack_networking_floatingip_v2.egress_vpn.address
}

output "egress_server_id" {
  value = openstack_compute_instance_v2.egress_vpn.id
}

output "wireguard_listen_port" {
  value = var.wg_listen_port
}

output "wireguard_public_ip_endpoint" {
  value = "${openstack_networking_floatingip_v2.egress_vpn.address}:${var.wg_listen_port}"
}

output "wireguard_domain_endpoint" {
  value = var.vpn_endpoint_mode == "domain" && trimspace(var.vpn_domain) != "" ? "${var.vpn_domain}:${var.wg_listen_port}" : ""
}

output "wireguard_endpoint" {
  value = var.vpn_endpoint_mode == "domain" && trimspace(var.vpn_domain) != "" ? "${var.vpn_domain}:${var.wg_listen_port}" : "${openstack_networking_floatingip_v2.egress_vpn.address}:${var.wg_listen_port}"
}
