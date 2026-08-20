variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "servers" {
  description = "Map of Kali servers to provision. Key = server_name = Ansible inventory hostname."
  type = map(object({
    server_type     = string # e.g. cx33
    server_location = string # e.g. fsn1
    server_image    = string # Phase-0 snapshot ID (numeric string), NOT a stock image name
    server_backups  = bool
    data_volume_gb  = number # persistent /home volume size
  }))
}

variable "ssh_public_key_path" {
  description = "Path to your public SSH key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_key_name" {
  description = "Name of existing SSH key in Hetzner Cloud (managed in infra-hetzner-ssh)"
  type        = string
  default     = "main-deploy-key"
}

variable "firewall_name" {
  description = "Name of existing firewall in Hetzner Cloud (managed in infra-hetzner-firewall)"
  type        = string
  default     = "kali-wg-firewall"
}

variable "lab_username" {
  description = "Interactive lab user (SSH + desktop)"
  type        = string
  default     = "lab"
}

variable "wg_listen_port" {
  description = "WireGuard UDP listen port on the server"
  type        = number
  default     = 51820
}

variable "wg_server_address" {
  description = "wg0 address of the server, CIDR form"
  type        = string
  default     = "10.99.0.1/24"
}

variable "wg_peer_address" {
  description = "wg0 address assigned to the operator peer (the Mac)"
  type        = string
  default     = "10.99.0.2/32"
}

variable "wg_peer_public_key" {
  description = "The operator peer's WireGuard PUBLIC key (generate on the Mac)"
  type        = string
}

variable "base_domain" {
  description = "Base domain used for FQDN / rDNS"
  type        = string
  default     = "example.com"
}

variable "timezone" {
  description = "Server timezone"
  type        = string
  default     = "Europe/Amsterdam"
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "production"
}

variable "managed_by" {
  description = "Infra management tool label"
  type        = string
  default     = "opentofu"
}
