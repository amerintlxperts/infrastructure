resource "azurerm_virtual_network" "hub_virtual_network" {
  name                = "hub_virtual_network"
  address_space       = [var.hub-virtual-network_address_prefix]
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_subnet" "hub-external_subnet" {
  address_prefixes     = [var.hub-external-subnet_prefix]
  name                 = var.hub-external-subnet_name
  resource_group_name  = azurerm_resource_group.azure_resource_group.name
  virtual_network_name = azurerm_virtual_network.hub_virtual_network.name
}

resource "azurerm_route_table" "hub_route_table" {
  name                = "hub_route_table"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  route {
    name           = "default"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "hub-external-route-table_association" {
  subnet_id      = azurerm_subnet.hub-external_subnet.id
  route_table_id = azurerm_route_table.hub_route_table.id
}

resource "azurerm_availability_set" "hub-nva_availability_set" {
  location                     = azurerm_resource_group.azure_resource_group.location
  resource_group_name          = azurerm_resource_group.azure_resource_group.name
  name                         = "hub-nva_availability_set"
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}
