output "resource_group_id" {
  value = data.azurerm_resource_group.rg.id
}

output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.vm.id
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "blob_container_name" {
  value = azurerm_storage_container.blob.name
}

output "key_vault_name" {
  value = azurerm_key_vault.key_vault.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.key_vault.vault_uri
}

output "vpn_gateway_public_ip" {
  value = azurerm_public_ip.vpn_gateway.ip_address
}

output "dns_resolver_inbound_ip" {
  value = azurerm_private_dns_resolver_inbound_endpoint.resolver.ip_configurations[0].private_ip_address
}

