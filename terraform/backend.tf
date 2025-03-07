# backend.tf
terraform {
  backend "azurerm" {
    subscription_id = var.subscription_id
    tenant_id       = var.tenant_id
    resource_group_name  = var.resource_group_name
    storage_account_name = var.storage_account_name
    container_name       = var.container_name
    key                  = "terraform.tfstate"
  }
}