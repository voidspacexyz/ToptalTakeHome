# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "env" {
  description = "Deployment environment name (used in all resource names and tags)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group that contains all project resources"
  type        = string
  default     = "RamToptal"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "CIDR block for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_aks_cidr" {
  description = "CIDR block for the AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_appgw_cidr" {
  description = "CIDR block for the Application Gateway subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_db_cidr" {
  description = "CIDR block for the PostgreSQL (database) subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# ---------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------

variable "pg_admin_username" {
  description = "Administrator username for the PostgreSQL Flexible Server"
  type        = string
  default     = "pgadmin"
}

variable "pg_admin_password" {
  description = "Administrator password for the PostgreSQL Flexible Server (store in Key Vault, override via TF_VAR_pg_admin_password)"
  type        = string
  sensitive   = true
}

variable "pg_database_name" {
  description = "Name of the initial application database"
  type        = string
  default     = "appdb"
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

variable "aks_system_node_count" {
  description = "Initial node count for the AKS system node pool"
  type        = number
  default     = 2
}

variable "aks_system_min_count" {
  description = "Minimum node count for the AKS system node pool autoscaler"
  type        = number
  default     = 2
}

variable "aks_system_max_count" {
  description = "Maximum node count for the AKS system node pool autoscaler"
  type        = number
  default     = 3
}

variable "aks_user_min_count" {
  description = "Minimum node count for the AKS user (workload) node pool autoscaler"
  type        = number
  default     = 2
}

variable "aks_user_max_count" {
  description = "Maximum node count for the AKS user (workload) node pool autoscaler"
  type        = number
  default     = 5
}
