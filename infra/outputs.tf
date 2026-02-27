# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the main resource group"
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the main resource group"
  value       = data.azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region in use"
  value       = data.azurerm_resource_group.main.location
}


# ---------------------------------------------------------------------------
# Networking — Phase 1.2
# ---------------------------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_aks_id" {
  description = "Resource ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "subnet_appgw_id" {
  description = "Resource ID of the Application Gateway subnet"
  value       = azurerm_subnet.appgw.id
}

output "subnet_db_id" {
  description = "Resource ID of the DB subnet"
  value       = azurerm_subnet.db.id
}

# ---------------------------------------------------------------------------
# Outputs populated by later phases (placeholders — populated as modules are added)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Azure Container Registry — Phase 1.3
# ---------------------------------------------------------------------------

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry (nodeprodacr)"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_admin_username" {
  description = "Admin username for ACR (bootstrap only; use managed identity in production)"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for ACR (bootstrap only; use managed identity in production)"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Azure Blob Storage — Phase 1.4
# ---------------------------------------------------------------------------

output "storage_account_name" {
  description = "Name of the Storage Account used for PostgreSQL backups"
  value       = azurerm_storage_account.backups.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the backup Storage Account (sensitive — store in Key Vault)"
  value       = azurerm_storage_account.backups.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary Blob service endpoint for the backup Storage Account"
  value       = azurerm_storage_account.backups.primary_blob_endpoint
}

output "postgres_backups_container_name" {
  description = "Name of the Blob container that holds PostgreSQL backup files"
  value       = azurerm_storage_container.postgres_backups.name
}

# ---------------------------------------------------------------------------
# Azure Key Vault — Phase 1.5
# ---------------------------------------------------------------------------

output "key_vault_name" {
  description = "Name of the Azure Key Vault used to store project secrets"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# ---------------------------------------------------------------------------
# PostgreSQL Flexible Server — Phase 1.5
# ---------------------------------------------------------------------------

output "postgresql_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgresql_fqdn" {
  description = "Internal FQDN of the PostgreSQL Flexible Server (private DNS zone)"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_database_name" {
  description = "Name of the initial application database"
  value       = azurerm_postgresql_flexible_server_database.app.name
}

output "app_rw_kv_secret_name" {
  description = "Key Vault secret name holding the app_rw PostgreSQL password (fetch: az keyvault secret show --vault-name <kv> --name app-rw-password)"
  value       = azurerm_key_vault_secret.app_rw_password.name
}

output "app_ro_kv_secret_name" {
  description = "Key Vault secret name holding the app_ro PostgreSQL password (fetch: az keyvault secret show --vault-name <kv> --name app-ro-password)"
  value       = azurerm_key_vault_secret.app_ro_password.name
}

# ---------------------------------------------------------------------------
# AKS — Phase 1.6
# ---------------------------------------------------------------------------

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS managed API server endpoint"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster (sensitive — use: tofu output -raw aks_kube_config_raw > ~/.kube/config)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "aks_node_resource_group" {
  description = "Auto-created resource group that contains AKS node VMs and infrastructure"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "aks_log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace used for Container Insights"
  value       = azurerm_log_analytics_workspace.aks.id
}

# ---------------------------------------------------------------------------
# Azure Cache for Redis — Phase 1.9
# ---------------------------------------------------------------------------

output "redis_name" {
  description = "Name of the Azure Cache for Redis instance"
  value       = azurerm_redis_cache.main.name
}

output "redis_hostname" {
  description = "Hostname of the Redis instance (private DNS resolves inside the VNet)"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_ssl_port" {
  description = "TLS/SSL port for the Redis instance (6380)"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_access_key" {
  description = "Primary access key for the Redis instance (sensitive — stored in Key Vault as 'redis-primary-access-key')"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_private_endpoint_id" {
  description = "Resource ID of the Redis private endpoint in the AKS subnet"
  value       = azurerm_private_endpoint.redis.id
}

# ---------------------------------------------------------------------------
# Application Gateway — Phase 1.7
# ---------------------------------------------------------------------------

output "appgw_public_ip" {
  description = "Public IP address of the Application Gateway (use as CDN origin and DNS A record)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_id" {
  description = "Resource ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "appgw_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "waf_policy_id" {
  description = "Resource ID of the WAF policy attached to the Application Gateway"
  value       = azurerm_web_application_firewall_policy.main.id
}

# ---------------------------------------------------------------------------
# Azure CDN — Phase 1.8 (Azure Front Door Standard)
# ---------------------------------------------------------------------------

output "cdn_profile_name" {
  description = "Name of the Azure Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.name
}

output "cdn_endpoint_name" {
  description = "Name of the Azure Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.name
}

output "cdn_endpoint_hostname" {
  description = "Hostname of the Front Door endpoint (*.azurefd.net) — use as DNS CNAME target"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}
