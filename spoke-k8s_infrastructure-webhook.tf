resource "kubernetes_namespace" "webhook" {
  depends_on = [
    azurerm_kubernetes_cluster.kubernetes_cluster
  ]
  metadata {
    name = "webhook"
    labels = {
      name = "webhook"
    }
  }
}

resource "kubernetes_secret" "webhook_fortiweb_login_secret" {
  count = var.APPLICATION_DOCS ? 1 : 0
  metadata {
    name      = "fortiweb-login-secret"
    namespace = kubernetes_namespace.webhook[0].metadata[0].name
  }
  data = {
    username = var.HUB_NVA_USERNAME
    password = var.HUB_NVA_PASSWORD
  }
  type = "Opaque"
}
