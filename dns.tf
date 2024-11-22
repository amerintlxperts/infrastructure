resource "azurerm_dns_zone" "dns_zone" {
  name                = var.DNS_ZONE
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}
