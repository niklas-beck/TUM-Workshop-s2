##################################################################################
# Main Terraform file 
##################################################################################

##################################################################################
# GET RESOURCE GROUP
##################################################################################

data "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
}


##################################################################################
# Storage Account
##################################################################################
resource "azurerm_storage_account" "storage_account" {
  name                     = var.basename
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_storage_container" "containercrt" {
  name                  = "critical"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "containerpub" {
  name                  = "public"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

##################################################################################
# Function App
##################################################################################
resource "azurerm_application_insights" "logging" {
  name                = "${var.basename}-ai"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  application_type    = "web"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_storage_account" "fxnstor" {
  name                     = "${var.basename}fx"
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_service_plan" "fxnapp" {
  name                = "${var.basename}-plan"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_linux_function_app" "fxn" {
  name                      = "funcApp-${var.basename}"
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.rg.name
  service_plan_id           = azurerm_service_plan.fxnapp.id
  storage_account_name       = azurerm_storage_account.fxnstor.name
  storage_account_access_key = azurerm_storage_account.fxnstor.primary_access_key

  site_config {
    application_insights_key               = azurerm_application_insights.logging.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.logging.connection_string
  }

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.logging.instrumentation_key
    SCM_DO_BUILD_DURING_DEPLOYMENT = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

##################################################################################
# Upload Files
##################################################################################

resource "azurerm_storage_blob" "publicblob" {
  for_each = fileset(path.module, "file_uploads/public/*")
 
  name                   = trimprefix(each.key, "file_uploads/public/")
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.containerpub.name
  type                   = "Block"
  source                 = each.key
}

resource "azurerm_storage_blob" "criticalblob" {
  for_each = fileset(path.module, "file_uploads/critical/*")
 
  name                   = trimprefix(each.key, "file_uploads/critical/")
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.containercrt.name
  type                   = "Block"
  source                 = each.key
}

##################################################################################
# Role Assignments
##################################################################################

// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-owner
// Provides full access to Azure Storage blob containers and data
resource "azurerm_role_assignment" "functionToStorage" {
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.fxn.identity[0].principal_id
}

##################################################################################
# Publishing function app
##################################################################################

resource "local_file" "app_deployment_script" {
  content  = <<CONTENT
#!/bin/bash

npm i -g azure-functions-core-tools@4 --unsafe-perm true

az functionapp config appsettings set -n ${azurerm_linux_function_app.fxn.name} -g ${data.azurerm_resource_group.rg.name} --settings "APPINSIGHTS_INSTRUMENTATIONKEY=""${azurerm_application_insights.logging.instrumentation_key}""" > /dev/null
cd ../src ; func azure functionapp publish ${azurerm_linux_function_app.fxn.name} --csharp ; cd ../terraform
CONTENT
  filename = "./deploy_function_app.sh"
}
