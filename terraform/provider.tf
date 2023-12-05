terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0"
    }

    random = {
      version = "~>2"
    }
  }

  backend "azurerm" {
    resource_group_name  = "TUM-Workshop"
    storage_account_name = "tfstoragetumworkshop"
    container_name       = "tum-workshop-session2"
    key                  = "repo-s2-temp.tfstate"
  }

}

provider "azurerm" {
  features {}
  use_oidc = true
}
