# ---------------------------------------------------------------------------
# Locals — shared across all modules
# ---------------------------------------------------------------------------

locals {
  # Standard tags applied to every Azure resource
  tags = {
    Owner   = "Ram"
    Purpose = "Toptal"
    Env     = var.env
  }

  # Name prefix derived from the environment variable; keeps names consistent
  # with the convention: node--<env>--<component>
  prefix = "node--${var.env}"
}

# ---------------------------------------------------------------------------
# Resource Group — already exists; reference it via data source
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# ---------------------------------------------------------------------------
# Networking — Phase 1.2
# ---------------------------------------------------------------------------

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}--vnet"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "aks" {
  name                 = "${local.prefix}--subnet--aks"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_aks_cidr]
}

# App Gateway subnet — delegations are not allowed; WAF_v2 requires its own /24+ subnet
resource "azurerm_subnet" "appgw" {
  name                 = "${local.prefix}--subnet--appgw"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_appgw_cidr]
}

# DB subnet — VNet delegation required for PostgreSQL Flexible Server
resource "azurerm_subnet" "db" {
  name                 = "${local.prefix}--subnet--db"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_db_cidr]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# ---------------------------------------------------------------------------
# Network Security Groups
# ---------------------------------------------------------------------------

# --- AKS NSG ---
resource "azurerm_network_security_group" "aks" {
  name                = "${local.prefix}--nsg--aks"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-db-internet-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "Internet"
    destination_address_prefix = var.subnet_db_cidr
  }
}

# --- App Gateway NSG ---
# WAF v2 requires GatewayManager (65200-65535) and AzureLoadBalancer to be allowed
resource "azurerm_network_security_group" "appgw" {
  name                = "${local.prefix}--nsg--appgw"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Required by Azure for Application Gateway v2 health and management traffic
  security_rule {
    name                       = "allow-gateway-manager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-azure-load-balancer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# --- DB NSG ---
# No internet ingress allowed; only PostgreSQL traffic from the AKS subnet
resource "azurerm_network_security_group" "db" {
  name                = "${local.prefix}--nsg--db"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "allow-postgres-from-aks"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.subnet_aks_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-internet-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# ---------------------------------------------------------------------------
# NSG ↔ Subnet Associations
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# ---------------------------------------------------------------------------
# Azure Container Registry — Phase 1.3
# ---------------------------------------------------------------------------
# ACR names must be globally unique, 5-50 chars, alphanumeric only (no hyphens).
# Logical alias used in tags/description: node--prod--acr
# Name derived by stripping '--' from the conventional prefix: nodeprodacr
locals {
  acr_name = replace("${local.prefix}--acr", "--", "")
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "Basic"

  # Admin credentials enabled for initial bootstrap (CI/CD will use service-principal or
  # managed-identity pull after AKS is attached via Phase 1.6)
  admin_enabled = true

  tags = merge(local.tags, {
    Alias = "${local.prefix}--acr"
  })
}

# ---------------------------------------------------------------------------
# Azure Blob Storage — Phase 1.4 (PostgreSQL backup target)
# ---------------------------------------------------------------------------
# Storage account names must be globally unique, lowercase alphanumeric, ≤24 chars.
# Logical alias used in tags: node--prod--blobstorage
# Name derived by stripping '--' from the conventional alias: nodeprodbackups
locals {
  storage_account_name = replace("${local.prefix}--backups", "--", "")
}

resource "azurerm_storage_account" "backups" {
  name                     = local.storage_account_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"

  # Enforce HTTPS for all requests
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  blob_properties {
    # Blob-level soft delete: 7-day retention
    delete_retention_policy {
      days = 7
    }

    # Container-level soft delete: 7-day retention
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(local.tags, {
    Alias = "${local.prefix}--blobstorage"
  })
}

resource "azurerm_storage_container" "postgres_backups" {
  name                  = "postgres-backups"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Phase 1.5 — Azure Key Vault + PostgreSQL Flexible Server
# ---------------------------------------------------------------------------

# Retrieve identity of the Terraform deployer (user or service principal).
# Used to grant Key Vault access so secrets can be written during apply.
data "azurerm_client_config" "current" {}

locals {
  # Key Vault names: 3-24 chars, alphanumeric + hyphens, must start with letter.
  # Double-hyphens are invalid, so convert node--prod--kv → node-prod-kv.
  key_vault_name = replace("${local.prefix}--kv", "--", "-")
}

# --- Azure Key Vault ---

resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.tags
}

# Grant the deployer identity full secret permissions so Terraform can write secrets on apply.
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# --- Private DNS Zone for PostgreSQL ---

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.prefix}--dns--postgres--link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

# --- PostgreSQL Flexible Server ---
# SKU: Burstable Standard_B1ms (1 vCPU, 2 GB RAM) as per plan.
# Storage: plan specified 5 GB Premium SSD; minimum available SKU for Flexible
# Server is 32 GB (32 768 MB / P4 tier) — using that minimum.
# Backup: LRS (geo_redundant_backup_enabled = false), 7-day retention.
# Network: private access only via delegated DB subnet + private DNS zone.

resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${local.prefix}--postgres"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  # Burstable tier — maps to "B_<vm-size>" in the provider
  sku_name = "B_Standard_B1ms"
  version  = "16"

  # Private-only access: must specify both the delegated subnet and the DNS zone.
  # public_network_access_enabled must be explicitly false — Azure rejects the
  # combination of VNet integration + public access (error 400 ConflictingPublicNetworkAccessAndVirtualNetworkConfiguration).
  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  administrator_login    = var.pg_admin_username
  administrator_password = var.pg_admin_password

  # 32 GB is the minimum storage available; plan target of 5 GB is not a valid SKU
  storage_mb   = 32768
  storage_tier = "P4" # Premium SSD P4 (32 GB)

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false # LRS as per plan

  tags = merge(local.tags, {
    Alias = "${local.prefix}--postgres"
  })

  # DNS zone link must exist before the server is created
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  # Azure auto-assigns an availability zone when none is specified; the provider
  # detects this as a diff on subsequent plans and tries to change it, which
  # the API rejects with "zone can only be changed when exchanged with the
  # standby_availability_zone".  Ignoring zone drift here is safe because we
  # don't use high-availability mode and have no zone pin requirement.
  lifecycle {
    ignore_changes = [zone]
  }
}

# --- Initial application database ---

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.pg_database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"

  # Prevent accidental destruction of the application database
  lifecycle {
    prevent_destroy = true
  }
}

# --- Store credentials in Key Vault ---

resource "azurerm_key_vault_secret" "pg_admin_username" {
  name         = "pg-admin-username"
  value        = var.pg_admin_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "pg_admin_password" {
  name         = "pg-admin-password"
  value        = var.pg_admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# ---------------------------------------------------------------------------
# Phase 1.6 — Azure Kubernetes Service (AKS)
# ---------------------------------------------------------------------------

# Log Analytics Workspace for Container Insights (Azure Monitor).
# Log Analytics workspace names cannot contain consecutive hyphens, so replace
# double-hyphens from the conventional prefix before constructing the name.
resource "azurerm_log_analytics_workspace" "aks" {
  name                = replace("${local.prefix}--law--aks", "--", "-")
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.prefix}--aks"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = replace("${local.prefix}-aks", "--", "-")

  # Standard tier provides a 99.5% uptime SLA for the control plane API server.
  # In azurerm >= 3.51 this supersedes the deprecated uptime_sla_enabled attribute.
  sku_tier = "Standard"

  # System-assigned managed identity — used for node pool operations and ACR pull
  identity {
    type = "SystemAssigned"
  }

  # RBAC is on by default; explicit here for clarity
  role_based_access_control_enabled = true

  # ---------------------------------------------------------------------------
  # System node pool (reserved for system pods: kube-system, CoreDNS, etc.)
  # SKU: Standard_B2s (2 vCPU, 4 GB RAM)
  # OS disk: Managed, 32 GB.
  # NOTE: The azurerm AKS provider does not expose the OS disk storage account
  #       type (Standard HDD vs Premium SSD) directly — the disk tier is
  #       determined by Azure based on the VM SKU.  Standard_B2s supports
  #       Premium SSD natively; requesting Standard HDD would require managing
  #       custom node images which is out of scope here.  We set the size to
  #       32 GB (matching the S4/P4 block size for cost parity) with Managed
  #       (non-ephemeral) type and no snapshot configuration.
  # ---------------------------------------------------------------------------
  default_node_pool {
    name    = "system"
    vm_size = "Standard_B2s"

    # Azure CNI requires the node pool to be placed in the AKS subnet
    vnet_subnet_id = azurerm_subnet.aks.id

    # Autoscaling: min 2 / max 3 with an initial count of 2
    enable_auto_scaling = true
    node_count          = var.aks_system_node_count
    min_count           = var.aks_system_min_count
    max_count           = var.aks_system_max_count

    # OS disk: 32 GB, Managed (non-ephemeral).  No snapshot policy configured.
    os_disk_size_gb = 32
    os_disk_type    = "Managed"

    # Taint this pool so only system/critical pods are scheduled here
    only_critical_addons_enabled = true

    tags = local.tags
  }

  # ---------------------------------------------------------------------------
  # Azure CNI networking — required for Application Gateway Ingress Controller
  # (AGIC), which needs pod IPs to be routeable from the App Gateway subnet.
  # Service CIDR must not overlap with any subnet in the VNet (10.0.0.0/16).
  # ---------------------------------------------------------------------------
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.100.0.0/16"
    dns_service_ip = "10.100.0.10"
  }

  # Container Insights — sends cluster, node, pod, and container metrics + logs
  # to the Log Analytics Workspace above.  MSI auth avoids storing workspace keys.
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.aks.id
    msi_auth_for_monitoring_enabled = true
  }

  # AGIC add-on — reuses the Application Gateway provisioned in Phase 1.7.
  # Providing gateway_id attaches AGIC to the existing AppGW rather than
  # creating a new one, preserving the WAF policy and probe configuration.
  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.main.id
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# User node pool — workload pods (web, api, etc.)
# Separate from the system pool so workloads don't share resources with
# kube-system components.
# SKU: Standard_B2s; autoscaling min 2 / max 5.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_B2s"

  vnet_subnet_id = azurerm_subnet.aks.id

  # Autoscaling: min 2 / max 5; initial count matches minimum
  enable_auto_scaling = true
  node_count          = var.aks_user_min_count
  min_count           = var.aks_user_min_count
  max_count           = var.aks_user_max_count

  os_disk_size_gb = 32
  os_disk_type    = "Managed"

  mode = "User"
  tags = local.tags
}

# ---------------------------------------------------------------------------
# ACR integration — grant the AKS kubelet identity the AcrPull role on the
# container registry so nodes can pull images without stored credentials.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"

  # kubelet_identity is the identity used by the node VMs to pull images
  principal_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# ---------------------------------------------------------------------------
# Phase 1.7 — Azure Application Gateway (WAF_v2) + AGIC
# ---------------------------------------------------------------------------

# Static public IP — WAF_v2 requires Standard SKU and Static allocation
resource "azurerm_public_ip" "appgw" {
  name                = "${local.prefix}--appgw--pip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# WAF Policy — Prevention mode with OWASP 3.2 core rule set
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "${local.prefix}--waf--policy"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = local.tags
}

# Application Gateway
# SKU: WAF_v2, 1 compute unit (manual scaling).
# Design constraints (not directly configurable in TF; enforced by the 1-CU
# capacity allocation and downstream architecture):
#   - Max persistent connections : 1 000
#   - Max throughput             : 2 MB/s
# AGIC dynamically manages backend pools, routing rules, listeners, and probes
# after cluster reconciliation; lifecycle.ignore_changes prevents config drift.
resource "azurerm_application_gateway" "main" {
  name                = "${local.prefix}--appgw"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  # WAF_v2, 1 compute unit, manual scaling
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  # Explicitly set a modern SSL policy to avoid the deprecated AppGwSslPolicy20150501 default.
  # AppGwSslPolicy20220101 enforces TLS 1.2 minimum with strong cipher suites.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-pip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "port-http"
    port = 80
  }

  # ---------------------------------------------------------------------------
  # Backend address pools — initially empty; AGIC populates them at runtime
  # ---------------------------------------------------------------------------

  backend_address_pool {
    name = "web-backend-pool"
  }

  backend_address_pool {
    name = "api-backend-pool"
  }

  # ---------------------------------------------------------------------------
  # Health probes — web tier (/) and API tier (/api/status)
  # ---------------------------------------------------------------------------

  probe {
    name                = "web-health-probe"
    protocol            = "Http"
    host                = "127.0.0.1"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    port                = 3000
    match {
      status_code = ["200-399"]
    }
  }

  probe {
    name                = "api-health-probe"
    protocol            = "Http"
    host                = "127.0.0.1"
    path                = "/api/status"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    port                = 3000
    match {
      status_code = ["200-399"]
    }
  }

  # ---------------------------------------------------------------------------
  # Backend HTTP settings
  # ---------------------------------------------------------------------------

  backend_http_settings {
    name                  = "web-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 3000
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "web-health-probe"
  }

  backend_http_settings {
    name                  = "api-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 3000
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "api-health-probe"
  }

  # Default HTTP listener on port 80
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-pip"
    frontend_port_name             = "port-http"
    protocol                       = "Http"
  }

  # Default routing rule — AGIC replaces this with path-based rules at runtime
  request_routing_rule {
    name                       = "default-routing-rule"
    rule_type                  = "Basic"
    priority                   = 10
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "web-backend-pool"
    backend_http_settings_name = "web-http-settings"
  }

  tags = merge(local.tags, {
    Alias = "${local.prefix}--appgw"
  })

  # AGIC reconciles backend pools, routing rules, listeners, probes, and
  # SSL certs at each Ingress controller sync.  Ignore those attributes here
  # to avoid perpetual "plan has changes" noise.
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      ssl_certificate,
      tags,
      url_path_map,
    ]
  }
}

# ---------------------------------------------------------------------------
# AGIC managed-identity role assignments
# The add-on provisions its own managed identity; we grant it the minimum
# roles required for AGIC to reconcile the Application Gateway.
# ---------------------------------------------------------------------------

# Contributor on the Application Gateway — needed to update AppGW configuration
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# Reader on the resource group — AGIC reads subnet and VNet metadata
resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# Network Contributor on the AppGW subnet — needed to manage frontend IPs
resource "azurerm_role_assignment" "agic_subnet_network_contributor" {
  scope                = azurerm_subnet.appgw.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

# ---------------------------------------------------------------------------
# Phase 1.9 — Azure Cache for Redis
# Basic C0 (250 MB). Public network access is disabled; a private endpoint
# in the AKS subnet provides connectivity from inside the VNet.
# TLS 1.2 enforced (SSL always on by default for Basic/Standard/Premium).
# Access key stored in Key Vault; hostname exposed as both an output and a
# Key Vault secret for pod injection.
# ---------------------------------------------------------------------------

resource "azurerm_redis_cache" "main" {
  # Azure Redis Cache names cannot contain consecutive hyphens; use single hyphens
  name                          = "node-${var.env}-redis"
  location                      = data.azurerm_resource_group.main.location
  resource_group_name           = data.azurerm_resource_group.main.name
  capacity                      = 0       # C0 — 250 MB cache
  family                        = "C"
  sku_name                      = "Basic"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = local.tags

  redis_configuration {}
}

# Private DNS zone for Redis private endpoint name resolution
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags
}

# Link the private DNS zone to the VNet so cluster nodes resolve the FQDN
resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "${local.prefix}--redis--dns-link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

# Private endpoint — placed in the AKS subnet (no public access)
resource "azurerm_private_endpoint" "redis" {
  name                = "${local.prefix}--redis--pe"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.aks.id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.prefix}--redis--psc"
    private_connection_resource_id = azurerm_redis_cache.main.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }
}

# Store Redis hostname in Key Vault
resource "azurerm_key_vault_secret" "redis_hostname" {
  name         = "redis-hostname"
  value        = azurerm_redis_cache.main.hostname
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.tags
  depends_on   = [azurerm_key_vault_access_policy.deployer]
}

# Store Redis primary access key in Key Vault
resource "azurerm_key_vault_secret" "redis_primary_access_key" {
  name         = "redis-primary-access-key"
  value        = azurerm_redis_cache.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.tags
  depends_on   = [azurerm_key_vault_access_policy.deployer]
}

# ---------------------------------------------------------------------------
# Phase 1.8 — Azure Front Door Standard
# Replaces retired Standard_Microsoft classic CDN (no longer accepts new
# profile creation as of 2025).  Front Door Standard provides the same
# edge-caching and HTTPS-redirect capabilities against the Application
# Gateway public IP as the single origin.
# ---------------------------------------------------------------------------

# Front Door profile — Standard_AzureFrontDoor
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${local.prefix}--cdn"
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.tags
}

# Front Door endpoint — exposes <name>.azurefd.net hostname
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${local.prefix}--cdn--endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = local.tags
}

# Origin group — holds the AppGW origin; health-probed over HTTP
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "appgw-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Http"
    interval_in_seconds = 30
  }
}

# Origin — Application Gateway public IP
resource "azurerm_cdn_frontdoor_origin" "appgw" {
  name                          = "appgw-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true

  host_name                      = azurerm_public_ip.appgw.ip_address
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_public_ip.appgw.ip_address
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false
}

# Rule set — container for delivery rules
resource "azurerm_cdn_frontdoor_rule_set" "main" {
  name                     = "deliveryrules"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

# Rule 1 — cache static assets under /public/* for 7 days
resource "azurerm_cdn_frontdoor_rule" "cache_static" {
  name                      = "CacheStaticAssets"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.main.id
  order                     = 1
  behavior_on_match         = "Continue"

  depends_on = [azurerm_cdn_frontdoor_origin_group.main]

  conditions {
    url_path_condition {
      operator         = "BeginsWith"
      negate_condition = false
      match_values     = ["/public/"]
      transforms       = ["Lowercase"]
    }
  }

  actions {
    route_configuration_override_action {
      cache_behavior                = "OverrideAlways"
      cache_duration                = "7.00:00:00"
      query_string_caching_behavior = "IgnoreQueryString"
      compression_enabled           = true
    }
  }
}

# Rule 2 — redirect plain HTTP to HTTPS (enforces HTTPS on the endpoint)
resource "azurerm_cdn_frontdoor_rule" "enforce_https" {
  name                      = "EnforceHttps"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.main.id
  order                     = 2
  behavior_on_match         = "Continue"

  depends_on = [azurerm_cdn_frontdoor_origin_group.main]

  conditions {
    request_scheme_condition {
      operator         = "Equal"
      negate_condition = false
      match_values     = ["HTTP"]
    }
  }

  actions {
    url_redirect_action {
      redirect_type        = "PermanentRedirect"
      redirect_protocol    = "Https"
      destination_hostname = ""
    }
  }
}

# Default route — binds endpoint → origin group, attaches rule set
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.appgw.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.main.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}
