# variables.tf

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
  default     = "SecureLine"
}

variable "network_security_group" {
  description = "Name of the existing network security group"
  type        = string
  default     = "Secureline"
}


variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "securelineVnet"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "securelineSubnet"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "securelinedemo"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "admin_username" {
  description = "Admin username for the virtual machine"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Path to the public SSH key"
  type        = string
  default     = "id_rsa.pub"
}

variable "ssh_private_key" {
  description = "Path to the private SSH key"
  type        = string
  default     = "id_rsa"
}

variable "dns_zone" {
  description = "Name of the DNS zone"
  default     = "demodomain.co"
}

variable "client_id" {
  description = "client id"
  type        = string
  default     = "f5e28e71-12d7-4b50-a739-51c144dab286"
}

variable "tenant_id" {
  description = "tenant id"
  type        = string
  default     = "563161ec-473b-4181-a08e-186bb8ba4131"
}

variable "subscription_id" {
  description = "subscription id"
  type        = string
  default     = "ec95ae66-f5f6-429b-b0f6-1212513218a9"
}

variable "client_secret" {
  description = "client secret"
  type        = string
  default     = "J1A8Q~T6jP~8G8sekr939lwNN4EQW~1MIp3lxcGt"
}

variable "azurerm_user_assigned_identity" {
  description = "user assigned identity"
  type        = string
  default     = "Secureline"
}

variable "storage_account_name" {
  description = "Size of the virtual machine"
  type        = string
  default     = "securelinestorage"
}

variable "container_name" {
  description = "container name"
  type        = string
  default     = "terraformstate"
  
}

