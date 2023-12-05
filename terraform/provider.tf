terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "TUM-Workshop"
    storage_account_name = "tfstoragetumworkshop"
    container_name       = "tum-workshop-session2"
    key                  = "repo-s2-temp.tfstate"
    use_oidc             = true
  }

}

provider "azurerm" {
  features {}
  use_oidc = true
}
