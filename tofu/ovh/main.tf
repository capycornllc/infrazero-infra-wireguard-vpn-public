provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "openstack" {
  auth_url  = var.openstack_auth_url
  user_name = var.openstack_user_name
  password  = var.openstack_password
  tenant_id = var.ovh_cloud_project_id
  region    = var.location
}

data "openstack_images_image_v2" "ubuntu" {
  name_regex  = var.server_image_regex
  most_recent = true
}

data "openstack_networking_network_v2" "ext_net" {
  name = var.ovh_ext_net_name
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

resource "openstack_networking_network_v2" "vpn" {
  name           = "${var.name_prefix}-vpn-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "vpn" {
  name       = "${var.name_prefix}-vpn-subnet"
  network_id = openstack_networking_network_v2.vpn.id
  cidr       = var.private_cidr
  ip_version = 4

  dns_nameservers = ["1.1.1.1", "8.8.8.8"]
}

resource "openstack_networking_router_v2" "vpn" {
  name                = "${var.name_prefix}-vpn-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}

resource "openstack_networking_router_interface_v2" "vpn" {
  router_id = openstack_networking_router_v2.vpn.id
  subnet_id = openstack_networking_subnet_v2.vpn.id
}

resource "openstack_networking_secgroup_v2" "vpn" {
  name        = "${var.name_prefix}-vpn-sg"
  description = "Infrazero WireGuard VPN egress security group"
}

resource "openstack_networking_secgroup_rule_v2" "vpn_wireguard" {
  security_group_id = openstack_networking_secgroup_v2.vpn.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = var.wg_listen_port
  port_range_max    = var.wg_listen_port
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "vpn_icmp" {
  security_group_id = openstack_networking_secgroup_v2.vpn.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_compute_instance_v2" "egress_vpn" {
  name            = "${var.name_prefix}-egress-vpn"
  image_id        = data.openstack_images_image_v2.ubuntu.id
  flavor_name     = var.egress_server_type
  security_groups = [openstack_networking_secgroup_v2.vpn.name]

  user_data = templatefile("${path.module}/templates/cloud-init.tftpl", {
    bootstrap_url            = local.bootstrap.url
    bootstrap_sha256         = local.bootstrap.sha256
    bootstrap_secrets_url    = var.bootstrap_secrets.url
    bootstrap_secrets_sha256 = var.bootstrap_secrets.sha256
    wg_listen_port           = tostring(var.wg_listen_port)
    wg_server_address        = var.wg_server_address
    wg_server_public_key     = var.wg_server_public_key
  })

  network {
    uuid = openstack_networking_network_v2.vpn.id
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  metadata = local.labels

  depends_on = [
    openstack_networking_subnet_v2.vpn,
    openstack_networking_router_interface_v2.vpn,
  ]
}

resource "openstack_networking_floatingip_v2" "egress_vpn" {
  pool = var.ovh_ext_net_name
}

resource "openstack_compute_floatingip_associate_v2" "egress_vpn" {
  floating_ip = openstack_networking_floatingip_v2.egress_vpn.address
  instance_id = openstack_compute_instance_v2.egress_vpn.id
}
