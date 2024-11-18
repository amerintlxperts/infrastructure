data "azurerm_public_ip" "hub-nva-vip_docs_public_ip" {
  count               = var.APPLICATION_DOCS ? 1 : 0
  name                = azurerm_public_ip.hub-nva-vip_docs_public_ip[0].name
  resource_group_name = azurerm_resource_group.azure_resource_group.name
}

resource "azurerm_public_ip" "hub-nva-vip_docs_public_ip" {
  count               = var.APPLICATION_DOCS ? 1 : 0
  name                = "hub-nva-vip_docs_public_ip"
  location            = azurerm_resource_group.azure_resource_group.location
  resource_group_name = azurerm_resource_group.azure_resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${azurerm_resource_group.azure_resource_group.name}-docs"
}

resource "kubernetes_namespace" "docs" {
  count = var.APPLICATION_DOCS ? 1 : 0
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "docs"
    labels = {
      name = "docs"
    }
  }
}

locals {
  htpasswd_content = "${var.HTUSERNAME}:${chomp(base64encode(var.HTPASSWD))}"
}

resource "kubernetes_secret" "htpasswd_secret" {
  count = var.APPLICATION_DOCS ? 1 : 0
  metadata {
    name      = "htpasswd-secret"
    namespace = kubernetes_namespace.docs[0].metadata[0].name
  }
  data = {
    htpasswd = local.htpasswd_content
  }
  type = "Opaque"
}

resource "kubernetes_secret" "docs_fortiweb_login_secret" {
  count = var.APPLICATION_DOCS ? 1 : 0
  metadata {
    name      = "fortiweb-login-secret"
    namespace = kubernetes_namespace.docs[0].metadata[0].name
  }
  data = {
    username = var.HUB_NVA_USERNAME
    password = var.HUB_NVA_PASSWORD
  }
  type = "Opaque"
}

locals {
  docs_manifest_repo_fqdn = "git@github.com:${var.GITHUB_ORG}/${var.MANIFESTS_APPLICATIONS_REPO_NAME}.git"
}

resource "azurerm_kubernetes_flux_configuration" "docs" {
  count                             = var.APPLICATION_DOCS ? 1 : 0
  name                              = "docs"
  cluster_id                        = azurerm_kubernetes_cluster.kubernetes_cluster.id
  namespace                         = "cluster-config"
  scope                             = "cluster"
  continuous_reconciliation_enabled = true
  git_repository {
    url                      = local.docs_manifest_repo_fqdn
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

resource "github_actions_secret" "ACR_LOGIN_SERVER" {
  count           = var.APPLICATION_DOCS ? 1 : 0
  repository      = var.DOCS_BUILDER_REPO_NAME
  secret_name     = "ACR_LOGIN_SERVER"
  plaintext_value = azurerm_container_registry.container_registry.login_server
}

resource "github_actions_secret" "DOCS_FQDN" {
  count           = var.APPLICATION_DOCS ? 1 : 0
  repository      = var.MANIFESTS_APPLICATIONS_REPO_NAME
  secret_name     = "DOCS_FQDN"
  plaintext_value = data.azurerm_public_ip.hub-nva-vip_docs_public_ip[0].fqdn
}

resource "null_resource" "trigger_docs_builder_workflow" {
  count = var.APPLICATION_DOCS ? 1 : 0

  # Define dependency on both github_actions_secret resources
  depends_on = [
    github_actions_secret.ACR_LOGIN_SERVER,
    github_actions_secret.DOCS_FQDN
  ]

  # Run the provisioner only after both secrets have been created
  provisioner "local-exec" {
    command = "gh workflow run docs-builder --repo ${var.GITHUB_ORG}/${var.DOCS_BUILDER_REPO_NAME} --ref main"
  }
}