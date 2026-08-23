locals {
  fqdn = { for k, _ in var.servers : k => "${k}.${var.base_domain}" }

  labels = {
    environment = var.environment
    managed_by  = var.managed_by
    os          = "kali"
    role        = "attacker"
  }
}
