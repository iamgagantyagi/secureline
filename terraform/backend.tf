# backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "SecureLine"
    storage_account_name = "securelinestorage"
    container_name       = "terraformstate"
    key                  = "terraform.tfstate"
  }
}
