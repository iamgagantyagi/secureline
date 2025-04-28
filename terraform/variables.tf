# variables.tf

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
  default     = "SecureLine"
}

variable "network_security_group" {
  description = "Name of the existing network security group"
  type        = string
  default     = "SecurelineNsg"
}


variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "centralindia"
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
  type        = string
  default     = "demodomain.co"
}

variable "create_dns_zone" {
  description = "Whether to create a new DNS zone or use an existing one"
  type        = bool
  default     = false
}

variable "dns_record_name" {
  description = "DNS A Record name"
  type        = string
  default     = "securelineArecord"
}


variable "client_id" {
  description = "client id"
  type        = string
}

variable "tenant_id" {
  description = "tenant id"
  type        = string
}

variable "subscription_id" {
  description = "subscription id"
  type        = string
}

variable "client_secret" {
  description = "client secret"
  type        = string
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

