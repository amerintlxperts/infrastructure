data "azurerm_public_ip" "hub-nva-vip_docs_public_ip" {
  name                = azurerm_public_ip.hub-nva-vip_docs_public_ip.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_dvwa_public_ip" {
  name                = azurerm_public_ip.hub-nva-vip_dvwa_public_ip.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_ollama_public_ip" {
  name                = azurerm_public_ip.hub-nva-vip_ollama_public_ip.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-vip_video_public_ip" {
  name                = azurerm_public_ip.hub-nva-vip_video_public_ip.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

data "azurerm_public_ip" "hub-nva-management_public_ip" {
  name                = azurerm_public_ip.hub-nva-management_public_ip.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}
