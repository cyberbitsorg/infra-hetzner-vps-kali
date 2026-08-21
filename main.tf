data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
}

data "hcloud_firewall" "default" {
  name = var.firewall_name
}

resource "random_password" "admin_password" {
  for_each = var.servers
  length   = 32
  special  = false
}

resource "random_password" "deployacc_sudo_password" {
  for_each = var.servers
  length   = 32
  special  = false
}

resource "hcloud_server" "kali" {
  for_each     = var.servers
  name         = each.key
  server_type  = each.value.server_type
  location     = each.value.server_location
  image        = each.value.server_image # Phase-0 snapshot ID
  backups      = each.value.server_backups
  ssh_keys     = [data.hcloud_ssh_key.default.id]
  firewall_ids = [data.hcloud_firewall.default.id]

  user_data = templatefile("${path.module}/cloud-init-bootstrap.yaml", {
    server_name             = each.key
    lab_username            = var.lab_username
    ssh_public_key          = file(pathexpand(var.ssh_public_key_path))
    timezone                = var.timezone
    fqdn                    = local.fqdn[each.key]
    admin_password          = random_password.admin_password[each.key].result
    deployacc_sudo_password = random_password.deployacc_sudo_password[each.key].result
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  labels = local.labels

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "hcloud_rdns" "ipv4" {
  for_each   = var.servers
  server_id  = hcloud_server.kali[each.key].id
  ip_address = hcloud_server.kali[each.key].ipv4_address
  dns_ptr    = local.fqdn[each.key]
}

resource "hcloud_volume" "home" {
  for_each = var.servers
  name     = "${each.key}-home"
  size     = each.value.data_volume_gb
  location = each.value.server_location
  format   = "ext4"
  labels   = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume_attachment" "home" {
  for_each  = var.servers
  volume_id = hcloud_volume.home[each.key].id
  server_id = hcloud_server.kali[each.key].id
  automount = false # Ansible does the seed-then-mount; never blind-mount over /home
}
