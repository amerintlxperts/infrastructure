data "azurerm_public_ip" "hub-nva-vip_docs_public_ip" {
  count               = var.APPLICATION_DOCS ? 1 : 0
  name                = azurerm_public_ip.hub-nva-vip_docs_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_dvwa_public_ip" {
  count               = var.APPLICATION_DVWA ? 1 : 0
  name                = azurerm_public_ip.hub-nva-vip_dvwa_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_ollama_public_ip" {
  count               = var.APPLICATION_OLLAMA ? 1 : 0
  name                = azurerm_public_ip.hub-nva-vip_ollama_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_video_public_ip" {
  count               = var.APPLICATION_VIDEO ? 1 : 0
  name                = azurerm_public_ip.hub-nva-vip_video_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-management_public_ip" {
  count               = var.PRODUCTION_ENVIRONMENT ? 0 : 1
  name                = azurerm_public_ip.hub-nva-management_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}
