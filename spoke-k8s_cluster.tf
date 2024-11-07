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
  name                = random_string.acr_name.result
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  location            = azurerm_resource_group.azure_resource_group.location
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
  #kubernetes_version                = data.azurerm_kubernetes_service_versions.current.latest_version
  #sku_tier = "Premium"
  #support_plan                      = "AKSLongTermSupport"
  #kubernetes_version                = "1.27"
  sku_tier                          = "Standard"
  cost_analysis_enabled             = true
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
    #type         = "UserAssigned"
    #identity_ids = [azurerm_user_assigned_identity.my_identity.id]
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

resource "kubernetes_namespace" "application" {
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "application"
    labels = {
      name = "application"
    }
  }
}

resource "kubernetes_secret" "fortiweb_login_secret" {
  metadata {
    name      = "fortiweb-login-secret"
    namespace = kubernetes_namespace.application.metadata[0].name
  }
  data = {
    username = var.HUB_NVA_USERNAME
    password = var.HUB_NVA_PASSWORD
  }
  type = "Opaque"
}

resource "kubernetes_namespace" "lacework-agent" {
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "lacework-agent"
    labels = {
      name = "lacework-agent"
    }
  }
}

resource "kubernetes_secret" "lacework_agent_token" {
  metadata {
    name      = "lacework-agent-token"
    namespace = kubernetes_namespace.lacework-agent.metadata[0].name
  }
  data = {
    "config.json" = jsonencode({
      tokens = {
        AccessToken = var.LW_AGENT_TOKEN
      },
      serverurl = "https://api.lacework.net",
      tags = {
        Env               = "k8s",
        KubernetesCluster = azurerm_kubernetes_cluster.kubernetes_cluster.name
      }
    }),
    "syscall_config.yaml" = ""
  }
}

locals {
  manifests_applications_repo_fqdn = "git@github.com:${var.MANIFESTS_APPLICATIONS_REPO_NAME}.git"
}

locals {
  manifests_infrastructure_repo_fqdn = "git@github.com:${var.MANIFESTS_INFRASTRUCTURE_REPO_NAME}.git"
}

resource "azurerm_kubernetes_flux_configuration" "docs" {
  count                             = var.APPLICATION_DOCS ? 1 : 0
  name                              = "docs"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.manifests_applications_repo_fqdn
    reference_type           = "branch"
    reference_value          = "docs-version"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_APPLICATIONS_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "docs"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./docs"
    sync_interval_in_seconds   = 60
  }
  depends_on = [
    azurerm_kubernetes_flux_configuration.infrastructure
  ]
}

resource "azurerm_kubernetes_flux_configuration" "video" {
  count                             = var.APPLICATION_VIDEO ? 1 : 0
  name                              = "video"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.manifests_applications_repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_APPLICATIONS_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "video"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./video"
    sync_interval_in_seconds   = 60
  }
  depends_on = [
    azurerm_kubernetes_flux_configuration.infrastructure
  ]
}

resource "azurerm_kubernetes_flux_configuration" "ollama" {
  count                             = var.APPLICATION_OLLAMA ? 1 : 0
  name                              = "ollama"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.manifests_applications_repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_APPLICATIONS_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "ollama"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = var.GPU_NODE_POOL ? "./ollama-gpu" : "./ollama-cpu"
    sync_interval_in_seconds   = 60
  }
  depends_on = [
    azurerm_kubernetes_flux_configuration.infrastructure
  ]
}

resource "azurerm_kubernetes_flux_configuration" "dvwa" {
  count                             = var.APPLICATION_OLLAMA ? 1 : 0
  name                              = "dvwa"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.manifests_applications_repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_APPLICATIONS_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "dvwa"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./dvwa"
    sync_interval_in_seconds   = 60
  }
  depends_on = [
    azurerm_kubernetes_flux_configuration.infrastructure
  ]
}

resource "azurerm_kubernetes_flux_configuration" "infrastructure" {
  name                              = "infrastructure"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.manifests_infrastructure_repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_INFRASTRUCTURE_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "infrastructure"
    recreating_enabled         = true
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
  }
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux_extension
  ]
}
