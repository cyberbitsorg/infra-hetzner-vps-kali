# infra-hetzner-vps-kali

OpenTofu + Ansible automation for a Kali Linux pentest VPS on Hetzner Cloud
(amd64, CX line, default `cx33`). RDP/desktop access is never exposed to the
public internet: it rides a WireGuard tunnel only.

Provisioning is two phases:

- **Phase 0**: `make image` builds a one-time Kali snapshot and prints its
  ID.
- **Phase 1**: `tofu apply` creates the server from that snapshot plus a
  persistent `/home` volume, then Ansible configures WireGuard, the desktop,
  and the toolset.

## Prerequisites

- `hcloud` CLI, `tofu`, `ansible-playbook`, `ssh`, `curl` installed locally.
- An SSH key already registered in Hetzner Cloud, managed by the sibling
  `infra-hetzner-ssh` repo (default name `main-deploy-key`).
- The `kali-wg-firewall` firewall already applied in Hetzner Cloud, managed
  by the sibling `infra-hetzner-firewall` repo. This repo does not create
  firewall rules; it only attaches to a firewall that must already exist. To
  create it: add the `kali` entry from
  `infra-hetzner-firewall/terraform.tfvars.example` to that repo's
  `terraform.tfvars` and run `tofu apply` **there**. The rules it opens
  publicly (`0.0.0.0/0`, because the operator IP roams) are:
  - `tcp/22`: SSH, key-only, backstopped by `fail2ban`.
  - `udp/51820`: WireGuard.
  - ICMP (ping): intentional and harmless; useful for reachability checks.

  No other ports are public. In particular, the desktop (xrdp) is never
  exposed here; it binds to the WireGuard interface address only, never the
  public IP.
- A WireGuard keypair generated on your Mac:

  ```bash
  wg genkey | tee privatekey | wg pubkey
  ```

  Keep `privatekey` local; you'll paste the **public** key into
  `terraform.tfvars`.

- `HCLOUD_TOKEN` exported in your shell for Phase 0 (`make image` uses
  `packer` with the `hcloud` plugin directly). Phase 1 reads the token from
  `terraform.tfvars` (`hcloud_token`).
- `packer` installed, with the Hetzner Cloud plugin:
  `packer plugins install github.com/hetznercloud/hcloud`.

## Phase 0: build the snapshot (one-time)

```bash
export HCLOUD_TOKEN=...
make image
```

This runs `packer build` against `packer/kali-image.pkr.hcl`, which:

1. Creates a **throwaway** builder server (`cx33`/`fsn1` by default, a
   plain Debian 12 image; the OS is irrelevant since the disk gets
   overwritten) and boots it into Hetzner's rescue system.
2. Resolves the current Kali GenericCloud amd64 artifact
   (`kali-linux-*-cloud-genericcloud-amd64.tar.xz`, which contains
   `disk.raw`) from `kali.download`, downloads it there, and **verifies its
   sha256 against the published `SHA256SUMS` before touching the disk**
   (via `scripts/lib/kali-image.sh`, uploaded and sourced on the builder).
3. Extracts `disk.raw` to a real file and `dd`s it onto `/dev/sda`.
4. Powers the server off and snapshots it, then deletes the throwaway
   server.

Packer prints the resulting **snapshot ID**. Copy it into
`terraform.tfvars` as `servers.<name>.server_image`. Re-run `make image`
whenever you want a refreshed Kali build; each run produces a new snapshot
ID and does not touch any running server.

## Phase 1: provision the server

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- `hcloud_token`: your Hetzner Cloud API token.
- `wg_peer_public_key`: the WireGuard public key generated above.
- `base_domain`: used to build the server's FQDN / rDNS PTR.
- `servers.<name>.server_image`: the snapshot ID from Phase 0.
- Optionally adjust `server_type` (default `cx33`), `server_location`
  (default `fsn1`), `data_volume_gb` (default `40`, the persistent
  `/home` volume size), and `lab_username` (default `lab`, the interactive
  SSH + desktop user cloud-init creates).
- Optionally adjust `kali_gui` (default `xfce`, or `none` for headless),
  `kali_toolset` (default `default`; also `curated`, `headless`, `large`),
  and `kali_mullvad` (default `false`). These are read by Ansible via
  `terraform.py`, the same way `wg_listen_port` already is.

Then:

```bash
tofu init
tofu apply
```

This creates, per entry in the `servers` map:

- An `hcloud_server` built from the Phase 0 snapshot, attached to the
  `kali-wg-firewall` firewall and the SSH key from `infra-hetzner-ssh`.
  `cloud-init-bootstrap.yaml` runs on first boot: creates the `deployacc`
  user (password sudo, used by Ansible) and the interactive
  `${lab_username}` user (default `lab`), locks down SSH to key-only /
  those two users, and disables root login.
- A reverse-DNS PTR record (`hcloud_rdns`) for the server's FQDN.
- A persistent `hcloud_volume` for `/home`. It is `prevent_destroy`d,
  because surviving server rebuilds is the point, and it is attached to the
  server but **not** auto-mounted; Ansible does the mount, deliberately, see
  below.

Wait for cloud-init to finish, then set up the Ansible Vault and run
Ansible:

```bash
ssh deployacc@<server-ip> 'cloud-init status --wait'
./ansible-vault-setup.sh
ansible-playbook -i ansible/inventory/terraform.py ansible/playbook.yaml
```

`ansible/inventory/terraform.py` is a dynamic inventory that shells out to
`tofu output -json`, so there is no static inventory file to keep in sync.
`deployacc`'s sudo is password-protected; `ansible-vault-setup.sh` reads
its password from `tofu output -json deployacc_sudo_password` and writes
it, encrypted, to `ansible/group_vars/all/vault.yaml` (prompting to create
`.vault_pass`, gitignored, on first run). Run it before the playbook;
Ansible has nothing to `become` with until the vault exists.

The playbook applies, in order:

1. **`common`**: timezone, base packages, unattended-upgrades, and a
   `fail2ban` sshd jail (backstop behind the key-only SSH).
2. **`wireguard_server`**: installs `wireguard-tools`, generates the
   server's WireGuard keypair on the box on first run (the private key
   never leaves it), renders `/etc/wireguard/wg0.conf` with the operator's
   public key (from `terraform.tfvars`) as the sole peer, and brings up
   `wg-quick@wg0`. **The server's WireGuard public key is printed in the
   Ansible output**; copy it into your Mac's `wg0.conf`.
3. **`persistence`**: mounts the persistent `/home` volume. On first use
   it formats the volume ext4, then **seeds it from the current `/home`
   (including `~/.ssh/authorized_keys`) before mounting it in place**.
   Never mount-then-populate, or the mount would bury the SSH key the
   session is authenticated with and lock you out. Subsequent runs detect
   the volume is already seeded/mounted and skip straight to the
   `mounted` state (idempotent).
4. **`kali_desktop`** (skipped when `kali_gui = "none"`): installs
   `kali-desktop-xfce` and `xrdp`, sets the lab user's session to XFCE, and,
   critically, **binds xrdp to the wg0 address only**
   (`port=tcp://10.99.0.1:3389` in `xrdp.ini`, ordered after `wg-quick@wg0`
   so the interface is up first), so RDP is unreachable from the public IP
   even if the cloud firewall were misconfigured.
5. **`kali_mullvad`** (only if `kali_mullvad = true`): installs the Mullvad
   VPN app (+ Mullvad Browser when there's a desktop) from Mullvad's own apt
   repo. `false` is a real removal (packages purged, repo and key taken back
   out), not a skip. Mullvad never auto-connects -- that stays a manual
   `mullvad account login` + `mullvad connect` on the box. Whenever it's
   installed, persistent nftables rules exempt SSH (22) and WireGuard
   (`wg_listen_port`) from Mullvad's tunnel enforcement, so a connected
   kill switch can't lock you out of managing the box -- this box is reached
   over its public IP, not a local range Mullvad's "allow LAN" would cover.
6. **`kali_toolset`**: installs the tier picked by `kali_toolset` --
   `curated` (a lean pentest set: `nmap`, `gobuster`, `sqlmap`,
   `metasploit-framework`, etc.), `headless`, `default` (`kali-linux-default`,
   the full meta-package), or `large`. `default`/`large` are big installs;
   the task runs async with a long poll.

## Connecting

1. Bring up WireGuard on the Mac using the private key you generated and
   the server's public key printed during the Ansible run:

   ```ini
   # wg0.conf
   [Interface]
   PrivateKey = <your Mac private key>
   Address = 10.99.0.2/32

   [Peer]
   PublicKey = <server public key, printed by the wireguard_server role>
   Endpoint = <server-ip>:51820
   AllowedIPs = 10.99.0.1/32
   ```

   ```bash
   wg-quick up wg0
   ```

2. RDP to `10.99.0.1` (only reachable once the tunnel is up) and log in to
   XFCE as `lab`.

3. SSH access (over the public IP, key-only): `ssh lab@<server-ip>` or
   `ssh deployacc@<server-ip>`.

## Persistence across rebuilds

`/home` lives entirely on the Hetzner volume, which is `prevent_destroy`d
in OpenTofu. Destroying and re-`apply`ing the server (e.g. to pick up a new
Phase 0 snapshot) does not touch the volume; re-running the `persistence`
role re-attaches and re-mounts it without re-seeding (the seed step only
fires when the volume looks empty), so files under `/home` survive a
rebuild.

### Destroying everything, including the volume

`prevent_destroy` only accepts a literal `true`/`false` in OpenTofu, so it
cannot be toggled from a `terraform.tfvars` variable. To wipe the box and
permanently delete `/home`, run:

```
make destroy-all
```

This flips `prevent_destroy` to `false` in [main.tf](main.tf) for the
duration of the destroy, then reverts the file with `git checkout`. If
`tofu destroy` fails or is aborted partway, `main.tf` is left with
`prevent_destroy = false` (`git status` will show it as modified) &mdash;
run `git checkout -- main.tf` manually before applying again.

## Operational constraints (abuse posture)

Hetzner monitors for scanning and acts on abuse reports against IPs in
their network. This box's public IP should be treated accordingly:

- Route THM/HTB/CTF and other lab traffic through the lab's own VPN, or
  Mullvad (`kali_mullvad = true`, see above), so Hetzner only ever sees
  encrypted tunnel traffic leaving the box.
- Avoid hosting callback listeners or payloads on the public IP; that
  traffic is visible to Hetzner and carries real suspension risk. Keep
  listeners inside lab VPNs where possible; treat anything exposed on the
  public IP as transient and burnable.
- Offensive traffic against real (non-lab) targets requires written
  authorisation. This repo does not open any standing public listener
  beyond SSH and WireGuard; everything else stays behind the tunnel.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
