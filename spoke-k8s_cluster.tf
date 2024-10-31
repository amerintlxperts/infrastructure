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
  sku                           = "Premium"
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
    node_count                  = var.environment == "production" ? 3 : 1
    vm_size                     = var.environment == "production" ? local.vm-image["aks"].size : local.vm-image["aks"].size-dev
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
  count                 = var.spoke-k8s-node-pool-gpu ? 1 : 0
  name                  = "gpu"
  mode                  = "User"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.kubernetes_cluster.id
  vm_size               = local.vm-image["aks"].gpu-size
  node_count            = 1
  os_sku                = "AzureLinux"
  node_taints           = ["nvidia.com/gpu=true:NoSchedule"]
  node_labels = {
    "nvidia.com/gpu.present" = "true"
  }
  os_disk_type      = "Ephemeral"
  ultra_ssd_enabled = true
  os_disk_size_gb   = "256"
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

resource "kubernetes_namespace" "lacework" {
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "lacework"
    labels = {
      name = "lacework"
    }
  }
}

resource "kubernetes_secret" "lacework_agent_token" {
  metadata {
    name      = "lacework_agent_token"
    namespace = kubernetes_namespace.lacework.metadata[0].name
  }
  data = {
    "config.json" = jsonencode({
      tokens = {
        AccessToken = var.LW_AGENT_TOKEN
      },
      serverurl = "https://api.lacework.net",
      tags = {
        Env              = "k8s",
        KubernetesCluster = azurerm_kubernetes_cluster.kubernetes_cluster.name
      }
    }),
    "syscall_config.yaml" = ""
  }
}

locals {
  repo_fqdn = "git@github.com:${var.MANIFESTS_REPO_NAME}.git"
}

resource "azurerm_kubernetes_flux_configuration" "flux_configuration" {
  name                              = "flux-configuration"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "infrastructure"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./infrastructure"
    sync_interval_in_seconds   = 60
  }
  kustomizations {
    name                       = "applications"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./applications"
    sync_interval_in_seconds   = 60
    depends_on                 = ["infrastructure"]
  }
  kustomizations {
    name                       = "ingress"
    recreating_enabled         = true
    garbage_collection_enabled = true
    path                       = "./ingress"
    sync_interval_in_seconds   = 60
    depends_on                 = ["applications"]
  }
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux_extension
  ]
}

resource "null_resource" "openapi_file" {
  depends_on = [azurerm_linux_virtual_machine.hub-nva_virtual_machine]
  #triggers = {
  #  always_run = timestamp()
  #}
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
TOKEN=$(echo "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"vdom\":\"root\"}" | base64 | tr -d "\\n")

#Create the swagger file
curl "https://$FQDN/api/v2.0/waf/openapi.openapischemafile" \
  -k \
  -H "Content-Type: multipart/form-data" \
  -H "Authorization:$TOKEN" \
  -F 'openapifile=@openapi.yaml' \
  --insecure "https://$FQDN/api/v2.0/waf/openapi.openapischemafile"

# attach swagger file to new policy

curl "https://$FQDN/api/v2.0/cmdb/waf/openapi-validation-policy" \
--insecure \
  -X 'POST' \
  -H "Authorization:$TOKEN" \
  -H 'Content-Type: application/json;charset=utf-8' \
  -H 'Pragma: no-cache' \
  -H 'Accept: application/json, text/plain, */*' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Cache-Control: no-cache' \
  -H 'Sec-Fetch-Mode: cors' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H 'Connection: keep-alive' \
  --data-binary '{"data":{"q_type":1,"name":"ollama","action":"alert","action_val":"2","block-period":600,"severity":"Low","severity_val":"3","trigger":"","trigger_val":"0","sz_schema-file":-1}}'

curl "https://$FQDN/api/v2.0/cmdb/waf/openapi-validation-policy/schema-file?mkey=ollama" \
  --insecure \
  -X 'POST' \
  -H 'Content-Type: application/json;charset=utf-8' \
  -H "Authorization:$TOKEN" \
  -H 'Pragma: no-cache' \
  -H 'Accept: application/json, text/plain, */*' \
  -H 'Connection: keep-alive' \
  --data-binary '{"data":{"openapi-file":"openapi.yaml"}}'

curl "https://$FQDN/api/v2.0/cmdb/waf/openapi-validation-policy?mkey=ollama" \
  --insecure \
  -H "Authorization:$TOKEN" \
  -X 'PUT' \
  -H 'Content-Type: application/json;charset=utf-8' \
  -H 'Pragma: no-cache' \
  -H 'Accept: application/json, text/plain, */*' \
  -H 'Cache-Control: no-cache' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H 'Connection: keep-alive' \
  --data-binary '{"data":{"can_view":0,"q_ref":0,"can_clone":1,"q_type":1,"name":"ollama","action":"alert","action_val":"2","block-period":600,"severity":"Low","severity_val":"3","trigger":"","trigger_val":"0","sz_schema-file":0}}'

# Create Custom Policy
curl "https://$FQDN/api/v2.0/cmdb/waf/web-protection-profile.inline-protection" \
  --insecure \
  -H "Authorization:$TOKEN" \
  -X 'POST' \
  -H 'Content-Type: application/json;charset=utf-8' \
  -H 'Pragma: no-cache' \
  -H 'Accept: application/json, text/plain, */*' \
  -H 'Connection: keep-alive' \
  --data-binary '{"data":{"name":"ollama","client-management":"enable","amf3-protocol-detection":"disable","mobile-app-identification":"disable","token-header":"Jwt-Token","ip-intelligence":"disable","fortigate-quarantined-ips":"disable","quarantined-ip-action":"alert","quarantined-ip-severity":"High","rdt-reason":"disable","openapi-validation-policy":"ollama"}}'
    EOT
    environment = {
      USERNAME = var.HUB_NVA_USERNAME
      PASSWORD = var.HUB_NVA_PASSWORD
      FQDN     = "${data.azurerm_public_ip.hub-nva-management_public_ip.fqdn}:${local.vm-image[var.hub-nva-image].management-port}"
    }
  }
}
