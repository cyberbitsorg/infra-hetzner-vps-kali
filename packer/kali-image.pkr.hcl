# Phase 0 (one-time): build the Kali snapshot via Packer's hcloud builder --
# rescue mode + dd raw image to /dev/sda, modeled on:
# https://tatusl.dev/posts/customized-hcloud-images-with-packer/
#
# A hand-rolled version of this (create server, enable rescue, ssh in, dd,
# then disable-rescue + reboot into the new OS + wait for SSH before
# snapshotting) reliably crashed the rescue kernel: rebooting it right after
# its own boot disk's partition table gets rewritten out from under it, live,
# turned out to be the trigger. Packer's flow never reboots the rescue kernel
# at all -- it powers the server off (hypervisor-level, no guest cooperation
# needed) and snapshots it off, which is what actually works.
#
# Requires: packer, the hcloud plugin (packer plugins install
# github.com/hetznercloud/hcloud), HCLOUD_TOKEN in env, an SSH key already in
# Hetzner matching ssh_key_name.

packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

variable "server_type" {
  type    = string
  default = "cx33"
}

variable "location" {
  type    = string
  default = "fsn1"
}

variable "ssh_key_name" {
  type    = string
  default = "main-deploy-key"
}

locals {
  snapshot_name = "kali-genericcloud-${formatdate("YYYYMMDD-hhmm", timestamp())}"
}

source "hcloud" "kali" {
  image         = "debian-12" # throwaway OS; we overwrite the disk
  location      = var.location
  server_type   = var.server_type
  ssh_username  = "root"
  ssh_keys      = [var.ssh_key_name]
  rescue        = "linux64"
  snapshot_name = local.snapshot_name
  snapshot_labels = {
    os   = "kali"
    role = "attacker"
  }
}

build {
  sources = ["source.hcloud.kali"]

  # Reuse the same URL/checksum resolution logic the test suite covers
  # (tests/kali-image.bats) instead of duplicating it inline here.
  provisioner "file" {
    source      = "../scripts/lib/kali-image.sh"
    destination = "/root/kali-image.sh"
  }

  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "set -euo pipefail",
      "cd /root",
      "source ./kali-image.sh",
      "index_html=$(curl -fsSL \"$KALI_BASE_URL\")",
      "img_url=$(kali_image_url \"$index_html\")",
      "file=$(basename \"$img_url\")",
      "sums=$(curl -fsSL \"$${KALI_BASE_URL}SHA256SUMS\")",
      "want=$(kali_want_sha \"$file\" \"$sums\")",
      "curl -fL \"$img_url\" -o \"$file\"",
      "got=$(sha256sum \"$file\" | awk '{print $1}')",
      "[ \"$want\" = \"$got\" ] || { echo \"CHECKSUM MISMATCH: want=$want got=$got\" >&2; exit 1; }",
      "echo \"checksum OK: $file\"",
      # disk.raw is a GNU old-style sparse tar member (~25GB nominal, ~1GB
      # real data). Extracting straight to a pipe (tar -xO | dd) corrupts
      # partway through: sparse-hole reconstruction needs lseek/ftruncate on
      # a real file, which a pipe can't provide. Extract to a real file first.
      "tar -xJf \"$file\" disk.raw",
      "dd if=disk.raw of=/dev/sda bs=4M status=progress",
      "sync"
    ]
  }
}
