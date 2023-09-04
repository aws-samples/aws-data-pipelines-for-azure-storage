# This Terraform Template is an example that demonstrates how to set up Azure resources for the Azure Blob to Amazon S3 Copy Solution.

### Create Azure Resource Group
resource "azurerm_resource_group" "ResourceGroup" {
  name     = format("%s%s%s%s", var.PrefixCode, "rsg", var.EnvironmentCode, "azs3copy")
  location = var.region_azure

  tags = {
    Provisioner = "Terraform"
    Owner       = var.OwnerTag
    Environment = var.EnvironmentTag
    Solution    = "azs3copy"
    rtype       = "scaffold"
  }
}

### Create Azure App Registration
data "azuread_client_config" "current" {}

resource "azuread_application" "AppRegistration" {
  display_name = format("%s%s%s%s", var.PrefixCode, "apr", var.EnvironmentCode, "azs3copy")
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "AppPassword" {
  display_name          = format("%s%s%s%s", var.PrefixCode, "app", var.EnvironmentCode, "azs3copy")
  application_object_id = azuread_application.AppRegistration.object_id
}

resource "azuread_service_principal" "ServicePrincipal" {
  application_id               = azuread_application.AppRegistration.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  feature_tags {
    enterprise = true
    gallery    = true
  }
}

### Create Azure Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "Logging" {
  name                = format("%s%s%s%s", var.PrefixCode, "law", var.EnvironmentCode, "azs3copy")
  location            = azurerm_resource_group.ResourceGroup.location
  resource_group_name = azurerm_resource_group.ResourceGroup.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

### Create Azure Storage
resource "azurerm_storage_account" "StorageAccount" {
  name                            = format("%s%s%s%s", var.PrefixCode, "sta", var.EnvironmentCode, "azs3copy")
  resource_group_name             = azurerm_resource_group.ResourceGroup.name
  location                        = azurerm_resource_group.ResourceGroup.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  #allowed_copy_scope              = "AAD" # This needs to be set to "From any Storage Accounts" but this option is not available yet. Change in GUI/API
  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 14
    }
  }
  tags = {
    Provisioner = "Terraform"
    Owner       = var.OwnerTag
    Environment = var.EnvironmentTag
    Solution    = "azs3copy"
    rtype       = "storage"
  }
}

resource "azurerm_monitor_diagnostic_setting" "StorageAccount" {
  name                       = format("%s%s%s%s", var.PrefixCode, "lad", var.EnvironmentCode, "azs3copy")
  target_resource_id         = "${azurerm_storage_account.StorageAccount.id}/blobServices/default/"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.Logging.id

  enabled_log {
    category = "StorageRead"
    
    retention_policy {
      enabled = false
    }
  }
  metric {
    category = "Capacity"

    retention_policy {
      days    = 0
      enabled = false
    }
  }
  metric {
    category = "Transaction"

    retention_policy {
      days    = 0
      enabled = false
    }
  }
}

resource "azurerm_log_analytics_storage_insights" "StorageInsights" {
  name                 = format("%s%s%s%s", var.PrefixCode, "las", var.EnvironmentCode, "azs3copy")
  resource_group_name  = azurerm_resource_group.ResourceGroup.name
  workspace_id         = azurerm_log_analytics_workspace.Logging.id
  storage_account_id   = azurerm_storage_account.StorageAccount.id
  storage_account_key  = azurerm_storage_account.StorageAccount.primary_access_key
  blob_container_names = ["blobExample_ok"]
}

resource "azurerm_storage_container" "StorageContainer" {

  name                  = format("%s%s%s%s", var.PrefixCode, "stc", var.EnvironmentCode, "azs3copy")
  storage_account_name  = azurerm_storage_account.StorageAccount.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "BlobDataContributor" {
  scope                = azurerm_storage_account.StorageAccount.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.ServicePrincipal.id
}

resource "azurerm_role_assignment" "BlobQueueContributor" {
  scope                = azurerm_storage_account.StorageAccount.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azuread_service_principal.ServicePrincipal.id
}

### Store Azure AD credentials in AWS Secrets Manager
data "azurerm_client_config" "current" {}

