# infra-hetzner-vps-kali

OpenTofu + Ansible automation for provisioning a Kali Linux VPS on Hetzner Cloud: a
Phase 0 step builds a hardened Kali snapshot image, and Phase 1 provisions the server,
WireGuard-only networking, and lab tooling from that snapshot.

## Quick start

**Phase 0 — build the snapshot (one-time)**

```bash
make image
```

**Phase 1 — provision the server**

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: hcloud_token, wg_peer_public_key, base_domain, servers.*.server_image
make validate
tofu apply
```

Full setup, WireGuard configuration, and operational details are documented separately
(see Task 14).
