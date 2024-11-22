resource "azurerm_user_assigned_identity" "cert-manager" {
  name                = "cert-manager"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  location            = azurerm_resource_group.azure_resource_group.location
}

resource "azurerm_role_assignment" "cert-manager_role_assignment" {
  principal_id   = azurerm_user_assigned_identity.cert-manager.principal_id
  role_definition_name = "DNS Zone Contributor"
  scope          = azurerm_dns_zone.dns_zone.id
}

resource "azurerm_federated_identity_credential" "cert-manager_federated_identity_credential" {
  name                = "cert-manager_federated_identity_credential"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.kubernetes_cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.cert-manager.id
  subject             = "system:serviceaccount:cert-manager:cert-manager"
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
  infrastructure_repo_fqdn = "git@github.com:${var.GITHUB_ORG}/${var.MANIFESTS_INFRASTRUCTURE_REPO_NAME}.git"
}

resource "azurerm_kubernetes_flux_configuration" "infrastructure" {
  name                              = "infrastructure"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.infrastructure_repo_fqdn
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
