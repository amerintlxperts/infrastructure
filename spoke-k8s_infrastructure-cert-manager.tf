resource "azurerm_user_assigned_identity" "cert-manager" {
  name                = "cert-manager"
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  location            = azurerm_resource_group.azure_resource_group.location
}

data "azurerm_user_assigned_identity" "cert_manager_data" {
  name                = azurerm_user_assigned_identity.cert-manager.name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  depends_on          = [azurerm_user_assigned_identity.cert-manager]
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

resource "kubernetes_manifest" "cert-manager_clusterissuer" {
  depends_on = [
    azurerm_kubernetes_flux_configuration.infrastructure
  ]
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "letsencrypt"
    }
    "spec" = {
      "acme" = {
        "server" = var.LETSENCRYPT_URL
        "email"  = var.OWNER_EMAIL
        "privateKeySecretRef" = {
          "name" = "letsencrypt"
        }
        "solvers" = [
          {
            "dns01" = {
              "azureDNS" = {
                "resourceGroupName" = azurerm_resource_group.azure_resource_group.name
                "subscriptionID"    = var.ARM_SUBSCRIPTION_ID
                "hostedZoneName"    = var.DNS_ZONE
                "environment"       = "AzurePublicCloud"
                "managedIdentity" = {
                  "clientID" = data.azurerm_user_assigned_identity.cert_manager_data.client_id
                }
              }
            }
          }
        ]
      }
    }
  }
}
