resource "kubernetes_namespace" "cert-manager" {
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "cert-manager"
    labels = {
      name = "cert-manager"
    }
  }
}

resource "kubernetes_secret" "cert-manager-azure-dns-credentials" {
  metadata {
    name      = "cert-manager-azure-dns-credentials"
    namespace = kubernetes_namespace.cert-manager.metadata[0].name
  }
  data = {
    subscriptionID = var.ARM_SUBSCRIPTION_ID
    clientID       = data.azurerm_user_assigned_identity.cert_manager_data.client_id
  }
  type = "Opaque"
}

resource "azurerm_user_assigned_identity" "cert-manager" {
  name                = "cert-manager"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  location            = azurerm_resource_group.azure_resource_group.location
}

data "azurerm_user_assigned_identity" "cert_manager_data" {
  name                = azurerm_user_assigned_identity.cert-manager.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_role_assignment" "cert-manager_role_assignment" {
  principal_id         = azurerm_user_assigned_identity.cert-manager.principal_id
  role_definition_name = "DNS Zone Contributor"
  scope                = azurerm_dns_zone.dns_zone.id
}

resource "azurerm_federated_identity_credential" "cert-manager_federated_identity_credential" {
  name                = "cert-manager_federated_identity_credential"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.kubernetes_cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.cert-manager.id
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

locals {
  cert-manager_repo_fqdn = "git@github.com:${var.GITHUB_ORG}/${var.MANIFESTS_INFRASTRUCTURE_REPO_NAME}.git"
}

resource "azurerm_kubernetes_flux_configuration" "cert-manager" {
  name                              = "cert-manager"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.cert-manager_repo_fqdn
    reference_type           = "branch"
    reference_value          = "main"
    sync_interval_in_seconds = 60
    ssh_private_key_base64   = base64encode(var.MANIFESTS_INFRASTRUCTURE_SSH_PRIVATE_KEY)
  }
  kustomizations {
    name                       = "cert-manager"
    recreating_enabled         = true
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
    path                       = "./cert-manager"
  }
  kustomizations {
    name                       = "cert-manager-clusterissuer"
    recreating_enabled         = true
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
    path                       = "./cert-manager-clusterissuer"
    depends_on                 = ["cert-manager"]
  }
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux_extension
  ]
}
