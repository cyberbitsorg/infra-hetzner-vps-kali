output "server_ip" {
  description = "Server IPv4 addresses, keyed by server name"
  value       = { for k, v in hcloud_server.kali : k => v.ipv4_address }
}

output "fqdn" {
  description = "FQDNs, keyed by server name (read by Ansible)"
  value       = local.fqdn
}

output "lab_username" {
  description = "Interactive lab user (read by Ansible)"
  value       = var.lab_username
}

output "base_domain" {
  value = var.base_domain
}

output "wg_server_address" {
  value = var.wg_server_address
}

output "wg_peer_address" {
  value = var.wg_peer_address
}

output "wg_peer_public_key" {
  value = var.wg_peer_public_key
}

output "wg_listen_port" {
  value = var.wg_listen_port
}

output "login_credentials" {
  description = "Initial lab passwords (change after first login), keyed by server name"
  value       = { for k, v in random_password.admin_password : k => v.result }
  sensitive   = true
}

output "deployacc_sudo_password" {
  description = "deployacc sudo passwords (deployacc uses NOPASSWD sudo, so this is unused), keyed by server name"
  value       = { for k, v in random_password.deployacc_sudo_password : k => v.result }
  sensitive   = true
}

output "data_volume_device" {
  description = "Stable by-id device path of the persistent /home volume, keyed by server"
  value       = { for k, v in hcloud_volume.home : k => "/dev/disk/by-id/scsi-0HC_Volume_${v.id}" }
}
