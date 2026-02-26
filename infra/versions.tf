terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state: Azure Blob Storage
  #
  # Bootstrap this storage account once before running `tofu init`:
  #   az group create -n RamToptal -l centralindia
  #   az storage account create -n nodeprodtfstate -g RamToptal \
  #     -l centralindia --sku Standard_LRS --kind StorageV2
  #   az storage container create -n tfstate \
  #     --account-name nodeprodtfstate
  #
  # Then run: tofu init
  # ---------------------------------------------------------------------------
  backend "azurerm" {
    resource_group_name  = "RamToptal"
    storage_account_name = "nodeprodtfstate"
    container_name       = "tfstate"
    key                  = "node-prod.tfstate"
  }
}
