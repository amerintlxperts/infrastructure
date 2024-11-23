locals {
  streams = [
    "Microsoft-ContainerLog",
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
    "Microsoft-KubePVInventory",
    "Microsoft-KubeServices",
    "Microsoft-KubeMonAgentEvents",
    "Microsoft-InsightsMetrics",
    "Microsoft-ContainerInventory",
    "Microsoft-ContainerNodeInventory",
    "Microsoft-Perf"
  ]
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

data "azurerm_kubernetes_service_versions" "current" {
  location        = azurerm_resource_group.azure_resource_group.location
  include_preview = false
}

resource "random_string" "acr_name" {
  length  = 25
  upper   = false
  special = false
  numeric = false
}

resource "azurerm_container_registry" "container_registry" {
  name                          = random_string.acr_name.result
  resource_group_name           = azurerm_resource_group.azure_resource_group.name
  location                      = azurerm_resource_group.azure_resource_group.location
  sku                           = var.PRODUCTION_ENVIRONMENT ? "Standard" : "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true
  anonymous_pull_enabled        = false
}

resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = "log-analytics"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_user_assigned_identity" "my_identity" {
  name                = "UserAssignedIdentity"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  location            = azurerm_resource_group.azure_resource_group.location
}

resource "azurerm_role_assignment" "kubernetes_contributor" {
  principal_id         = azurerm_user_assigned_identity.my_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_resource_group.azure_resource_group.id
}

resource "azurerm_role_assignment" "route_table_network_contributor" {
  principal_id                     = azurerm_user_assigned_identity.my_identity.principal_id
  role_definition_name             = "Network Contributor"
  scope                            = azurerm_resource_group.azure_resource_group.id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "acr_role_assignment" {
  principal_id                     = azurerm_kubernetes_cluster.kubernetes_cluster.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.container_registry.id
  skip_service_principal_aad_check = true
}

locals {
  cluster_name        = substr("${azurerm_resource_group.azure_resource_group.name}_k8s-cluster_${var.LOCATION}", 0, 63)
  node_resource_group = substr("${azurerm_resource_group.azure_resource_group.name}_k8s-cluster_${var.LOCATION}_MC", 0, 80)
}

resource "azurerm_kubernetes_cluster" "kubernetes_cluster" {
  depends_on          = [azurerm_virtual_network_peering.spoke-to-hub_virtual_network_peering, azurerm_linux_virtual_machine.hub-nva_virtual_machine]
  name                = local.cluster_name
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  dns_prefix          = azurerm_resource_group.azure_resource_group.name
  sku_tier                          = var.PRODUCTION_ENVIRONMENT ? "Standard" : "Free"
  cost_analysis_enabled             = var.PRODUCTION_ENVIRONMENT ? true : false
  support_plan                      = "KubernetesOfficial"
  kubernetes_version                = "1.30"
  node_resource_group               = local.node_resource_group
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  #api_server_access_profile {
  #  authorized_ip_ranges = [
  #    "${chomp(data.http.myip.response_body)}/32"
  #  ]
  #}
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.log_analytics.id
    msi_auth_for_monitoring_enabled = true
  }
  default_node_pool {
    temporary_name_for_rotation = "rotation"
    name                        = "system"
    node_count                  = var.PRODUCTION_ENVIRONMENT == "Production" ? 3 : 1
    vm_size                     = var.PRODUCTION_ENVIRONMENT == "Production" ? local.vm-image["aks"].size : local.vm-image["aks"].size-dev
    os_sku                      = "AzureLinux"
    max_pods                    = "75"
    orchestrator_version        = "1.30"
    vnet_subnet_id              = azurerm_subnet.spoke_subnet.id
    upgrade_settings {
      max_surge = "10%"
    }
  }
  network_profile {
    #network_plugin    = "azure"
    network_plugin = "kubenet"
    #network_plugin = "none"
    #outbound_type     = "loadBalancer" 
    #network_policy    = "azure"
    load_balancer_sku = "standard"
    #service_cidr      = var.spoke-aks-subnet_prefix
    #dns_service_ip    = var.spoke-aks_dns_service_ip
    pod_cidr = var.spoke-aks_pod_cidr
  }
  identity {
    type = "SystemAssigned"
  }
}

data "azurerm_resource_group" "managed_rg" {
  name = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
}

resource "azurerm_resource_group" "tagged_managed_rg" {
  name     = data.azurerm_resource_group.managed_rg.name
  location = data.azurerm_resource_group.managed_rg.location
  tags = {
    Username = var.OWNER_EMAIL
    Name     = var.NAME
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "node-pool" {
  count                 = var.GPU_NODE_POOL ? 1 : 0
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.kubernetes_cluster.id
  vm_size               = var.PRODUCTION_ENVIRONMENT ? local.vm-image["aks"].gpu-size : local.vm-image["aks"].gpu-size-dev
  os_sku                = "AzureLinux"
  auto_scaling_enabled  = var.PRODUCTION_ENVIRONMENT
  node_count            = 1
  node_taints           = ["nvidia.com/gpu=true:NoSchedule"]
  node_labels = {
    "nvidia.com/gpu.present" = "true"
  }
  os_disk_type      = "Ephemeral"
  ultra_ssd_enabled = true
  os_disk_size_gb   = var.PRODUCTION_ENVIRONMENT == "Production" ? "256" : "175"
  max_pods          = "50"
  zones             = ["1"]
  vnet_subnet_id    = azurerm_subnet.spoke_subnet.id
}

#resource "azurerm_monitor_data_collection_rule" "data_collection_rule" {
#  name                = "rule_${azurerm_resource_group.azure_resource_group.name}_${azurerm_resource_group.azure_resource_group.location}"
#  resource_group_name = azurerm_resource_group.azure_resource_group.name
#  location            = azurerm_resource_group.azure_resource_group.location
#  destinations {
#    log_analytics {
#      workspace_resource_id = azurerm_log_analytics_workspace.log_analytics.id
#      name                  = "ciworkspace"
#    }
#  }
#  data_flow {
#    streams      = local.streams
#    destinations = ["ciworkspace"]
#  }
#  data_sources {
#    extension {
#      streams        = local.streams
#      extension_name = "ContainerInsights"
#      extension_json = jsonencode({
#        "dataCollectionSettings" : {
#          "interval" : "1m",
#          "namespaceFilteringMode" : "Off",
#          "namespaces" : ["kube-system", "gatekeeper-system", "azure-arc"],
#          "enableContainerLogV2" : true
#        }
#      })
#      name = "ContainerInsightsExtension"
#    }
#  }
#  description = "DCR for Azure Monitor Container Insights"
#}

#resource "azurerm_monitor_data_collection_rule_association" "data_collection_rule_association" {
#  name                    = "ruleassoc-${azurerm_resource_group.azure_resource_group.name}-${azurerm_resource_group.azure_resource_group.location}"
#  target_resource_id      = azurerm_kubernetes_cluster.kubernetes_cluster.id
#  data_collection_rule_id = azurerm_monitor_data_collection_rule.data_collection_rule.id
#  description             = "Association of container insights data collection rule. Deleting this association will break the data collection for this AKS Cluster."
#}

resource "azurerm_kubernetes_cluster_extension" "flux_extension" {
  name              = "flux-extension"
  cluster_id        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  extension_type    = "microsoft.flux"
  release_namespace = "flux-system"
  depends_on        = [azurerm_kubernetes_cluster.kubernetes_cluster]
  configuration_settings = {
    "image-automation-controller.enabled" = true,
    "image-reflector-controller.enabled"  = true,
    "helm-controller.detectDrift"         = true,
    "notification-controller.enabled"     = true
  }
}


