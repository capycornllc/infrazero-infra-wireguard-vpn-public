# Scripts

This directory will contain the VPN-only deploy scripts.

Initial planned split:

- `provision-egress`: create or update the Hetzner egress server.
- `configure-wireguard`: install WireGuard and render server/peer config.
- `export-clients`: prepare client configuration artifacts.

The current repository intentionally has no executable deployment scripts yet.
