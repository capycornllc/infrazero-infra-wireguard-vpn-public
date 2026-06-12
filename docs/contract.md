# WireGuard VPN Deploy Contract

The Infrazero backend will prepare the VPN deploy payload independently from the
application deploy payload.

## GitHub Secrets

The first backend skeleton prepares these values:

- `HETZNER_CLOUD_TOKEN` (Hetzner only)
- `OVH_APPLICATION_KEY` (OVHcloud only)
- `OVH_APPLICATION_SECRET` (OVHcloud only)
- `OVH_CONSUMER_KEY` (OVHcloud only)
- `OVH_CLOUD_PROJECT_ID` (OVHcloud only)
- `OPENSTACK_USER_NAME` (OVHcloud only)
- `OPENSTACK_PASSWORD` (OVHcloud only)
- `OPENSTACK_AUTH_URL` (OVHcloud only)
- `OVH_ENDPOINT` (OVHcloud only)
- `OVH_EXT_NET_NAME` (OVHcloud only)
- `CLOUDFLARE_API_TOKEN`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_REGION`
- `S3_ENDPOINT`
- `INFRA_STATE_BUCKET`
- `VPN_PROJECT_SLUG`
- `VPN_ENVIRONMENT`
- `VPN_CLOUD_PROVIDER`
- `VPN_CLOUD_REGION`
- `VPN_EGRESS_SERVER_TYPE`
- `VPN_ENDPOINT_MODE`
- `VPN_DOMAIN`
- `VPN_ROUTING_MODE`
- `VPN_SPLIT_ALLOWED_IPS`
- `VPN_CLIENT_DNS`
- `WG_LISTEN_PORT`
- `WG_SERVER_ADDRESS`
- `WG_SERVER_PRIVATE_KEY`
- `WG_SERVER_PUBLIC_KEY`
- `VPN_PEERS_JSON`

`VPN_PEERS_JSON` contains enabled peers only and includes each peer address,
public key, and preshared key. It must never include client private keys.
Client private keys are delivered only in the local encrypted credentials ZIP.

## Security Notes

- Application admins and VPN peers are different domains.
- Secrets are written only as GitHub Actions secrets by the Infrazero deploy integration.
- The infra workflow offloads WireGuard bootstrap secrets to a short-lived S3
  object and passes only a presigned URL plus SHA-256 through OpenTofu
  `user_data`.
- Private keys must not be committed to this repository.
- Scripts should fail closed when required secrets are missing.

## Script Responsibilities

Future scripts should keep responsibilities narrow:

- provision one provider-specific egress server from `tofu/hetzner` or `tofu/ovh`;
- install and configure WireGuard;
- enable IPv4 forwarding and NAT for the selected routing mode;
- generate client config artifacts from `VPN_PEERS_JSON`;
- expose deploy outputs without printing private keys.

## Deploy Outputs

After `tofu apply`, the workflow writes a public artifact named
`vpn-deploy-output` with `vpn-deploy-output.json`.

The artifact includes:

- `egressPublicIpv4`
- `wireguardEndpoint`
- `publicIpEndpoint`
- `domainEndpoint`
- `clientConfigPatch.placeholder`
- `clientConfigPatch.replacement`

It must not include tokens, server private keys, client private keys, or
preshared keys. In public IP mode, `wireguardEndpoint` is the post-apply source
of truth, matching the application infra pattern where public IPs come from
OpenTofu outputs.
