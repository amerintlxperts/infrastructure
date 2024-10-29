resource "github_actions_secret" "ACR_LOGIN_SERVER" {
  #repository      = var.DOCS_BUILDER_REPO_NAME
  repository = "amerintlxperts/docs-builder"
  secret_name     = "ACR_LOGIN_SERVER"
  plaintext_value = azurerm_container_registry.container_registry.login_server
}
