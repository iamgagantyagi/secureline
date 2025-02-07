# backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "SecureLine"
    storage_account_name = "securlinestorage"
    container_name       = "terraformstate"
    key                  = "terraform.tfstate"
  }
}
