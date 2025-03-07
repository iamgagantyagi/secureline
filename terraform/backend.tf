# backend.tf
terraform {
  backend "azurerm" {
    subscription_id = "ec95ae66-f5f6-429b-b0f6-1212513218a9"
    tenant_id       = "563161ec-473b-4181-a08e-186bb8ba4131"
    resource_group_name  = "Secureline"
    storage_account_name = "securelinestorage"
    container_name       = "terraformstate"
    key                  = "terraform.tfstate"
  }
}