resource "azurerm_dns_zone" "dns_zone" {
  name                = var.DNS_ZONE
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_virtual_network" "hub_virtual_network" {
  name                = "hub_virtual_network"
  address_space       = [var.hub-virtual-network_address_prefix]
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_virtual_network_peering" "hub-to-spoke_virtual_network_peering" {
  name                      = "hub-to-spoke_virtual_network_peering"
  resource_group_name       = azurerm_resource_group.azure_resource_group.name
  virtual_network_name      = azurerm_virtual_network.hub_virtual_network.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_virtual_network.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
  depends_on                = [azurerm_virtual_network.hub_virtual_network, azurerm_virtual_network.spoke_virtual_network]
}

resource "azurerm_subnet" "hub-external_subnet" {
  address_prefixes     = [var.hub-external-subnet_prefix]
  name                 = var.hub-external-subnet_name
  resource_group_name  = azurerm_resource_group.azure_resource_group.name
  virtual_network_name = azurerm_virtual_network.hub_virtual_network.name
}

resource "azurerm_subnet" "hub-internal_subnet" {
  address_prefixes     = [var.hub-internal-subnet_prefix]
  name                 = var.hub-internal-subnet_name
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

resource "azurerm_subnet_route_table_association" "hub-internal-routing-table_association" {
  subnet_id      = azurerm_subnet.hub-internal_subnet.id
  route_table_id = azurerm_route_table.hub_route_table.id
}

resource "azurerm_subnet_route_table_association" "hub-external-route-table_association" {
  subnet_id      = azurerm_subnet.hub-external_subnet.id
  route_table_id = azurerm_route_table.hub_route_table.id
}

resource "azurerm_network_security_group" "hub-external_network_security_group" { #tfsec:ignore:azure-network-no-public-ingress
  name                = "hub-external_network_security_group"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  security_rule {
    name                       = "MGMT_rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = local.vm-image[var.hub-nva-image].management-port
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-management-ip
  }
  security_rule {
    name                       = "VIP_rule-docs"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"] #checkov:skip=CKV_AZURE_160: Allow HTTP redirects
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-vip-docs
  }
  security_rule {
    name                       = "VIP_rule-dvwa"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"] #checkov:skip=CKV_AZURE_160: Allow HTTP redirects
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-vip-dvwa
  }
  security_rule {
    name                       = "VIP_rule-ollama"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"] #checkov:skip=CKV_AZURE_160: Allow HTTP redirects
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-vip-ollama
  }
  security_rule {
    name                       = "VIP_rule-video"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"] #checkov:skip=CKV_AZURE_160: Allow HTTP redirects
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-vip-video
  }
  security_rule {
    name                       = "VIP_rule-extractor"
    priority                   = 105
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"] #checkov:skip=CKV_AZURE_160: Allow HTTP redirects
    source_address_prefix      = "*"
    destination_address_prefix = var.hub-nva-vip-extractor
  }
}

resource "azurerm_subnet_network_security_group_association" "hub-external-subnet-network-security-group_association" {
  subnet_id                 = azurerm_subnet.hub-external_subnet.id
  network_security_group_id = azurerm_network_security_group.hub-external_network_security_group.id
}

resource "azurerm_network_security_group" "hub-internal_network_security_group" {
  name                = "hub-internal_network_security_group"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  security_rule {
    name                    = "aks-node_to_internet_rule"
    priority                = 100
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_ranges = ["80", "443"]
    #source_address_prefix      = var.spoke-aks-node-ip
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "*"
  }
  security_rule {
    name                   = "icmp_to_google-dns_rule"
    priority               = 101
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Icmp"
    source_port_range      = "*"
    destination_port_range = "*"
    #source_address_prefix      = var.spoke-aks-node-ip
    source_address_prefix = "*"
    #destination_address_prefix = var.spoke-check-internet-up-ip
    destination_address_prefix = "*"
  }
  security_rule {
    name                    = "outbound-http_rule"
    priority                = 102
    direction               = "Outbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_ranges = ["8000", "8080", "11434"]
    source_address_prefix   = "*"
    #destination_address_prefix = var.spoke-aks-node-ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "hub-internal-subnet-network-security-group_association" {
  subnet_id                 = azurerm_subnet.hub-internal_subnet.id
  network_security_group_id = azurerm_network_security_group.hub-internal_network_security_group.id
}
