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

resource "kubernetes_secret" "godaddy-api-key" {
  metadata {
    name      = "godaddy-api-key"
    namespace = kubernetes_namespace.cert-manager.metadata[0].name
  }
  type = "Opaque"
  data = {
    token = base64encode("${var.GODADDY_API_KEY}:${var.GODADDY_SECRET_KEY}")
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
