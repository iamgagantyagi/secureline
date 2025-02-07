
# Configure the Azure provider
provider "azurerm" {
  subscription_id = "ec95ae66-f5f6-429b-b0f6-1212513218a9"
  #client_id       = "your_client_id"
  #client_secret   = "your_client_secret"
  #tenant_id       = "563161ec-473b-4181-a08e-186bb8ba4131"
  
  
  features {}
}

data "azurerm_resource_group" "existing_rg" {
  name = var.resource_group_name
}

data "azurerm_network_security_group" "existing_nsg" {
  name = var.network_security_group
  resource_group_name = data.azurerm_resource_group.existing_rg.name

}

data "azurerm_user_assigned_identity" "example" {
  name                = var.azurerm_user_assigned_identity
  resource_group_name = data.azurerm_resource_group.existing_rg.name
}



# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  #location            = data.azurerm_resource_group.existing_rg.location
  location            = var.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = data.azurerm_resource_group.existing_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

}

resource "azurerm_subnet_network_security_group_association" "networknsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = data.azurerm_network_security_group.existing_nsg.id
#  resource_group_name  = data.azurerm_resource_group.existing_rg.nam

}

# Create a public IP address
resource "azurerm_public_ip" "publicip" {
  name                = "${var.vm_name}-publicip"
  #location            = data.azurerm_resource_group.existing_rg.location
  location             = var.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create a network interface
resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  #location            = data.azurerm_resource_group.existing_rg.location
  location            = var.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name

  ip_configuration {
    name                          = "myNICConfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

# Create an Ubuntu virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  #location              = data.azurerm_resource_group.existing_rg.location
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.existing_rg.name
  user_data             = base64encode(file("${path.module}/userdata.sh.tpl"))
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                  = var.vm_size

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = var.vm_name
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key)
  }  

  identity {
    type = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.example.id]
  } 
  depends_on = [azurerm_public_ip.publicip]
}

# Output the public IP address
output "public_ip_address" {
  value = azurerm_public_ip.publicip.ip_address
}

resource "time_sleep" "wait_for_vm" {
  depends_on = [azurerm_linux_virtual_machine.vm]
  create_duration = "600s"
}

data "azurerm_dns_zone" "existing_domain" {
  name = var.dns_zone
}
# Create DNS zone
#resource "azurerm_dns_zone" "example" {
 # name                = var.dns_zone
 # resource_group_name   = data.azurerm_resource_group.existing_rg.name
#}

# Create DNS A record using the public IP address
resource "azurerm_dns_a_record" "devops_org" {
  name                = "securelineArecord"
  zone_name           = data.azurerm_dns_zone.existing_domain.name
  resource_group_name   = data.azurerm_resource_group.existing_rg.name
  ttl                 = 300
  records             = [azurerm_public_ip.publicip.ip_address]  # Use the obtained public IP address
}

resource "null_resource" "vm_provisioner" {
  depends_on = [azurerm_linux_virtual_machine.vm, azurerm_public_ip.publicip, time_sleep.wait_for_vm]
    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key)
      host        = azurerm_public_ip.publicip.ip_address
    }
  provisioner "file" {
  source      = "./defectdojo.yaml"  # Local path on your Windows machine
  destination = "/home/ubuntu/defectdojo.yaml"   # Destination on the remote machine
}    
  provisioner "file" {
  source      = "./setup.sh"  # Local path on your Windows machine
  destination = "/home/ubuntu/setup.sh"     # Destination on the remote machine
}  
  provisioner "file" {
  source      = "./dd.py"  # Local path on your Windows machine
  destination = "/home/ubuntu/dd.py"     # Destination on the remote machine
}  
  provisioner "file" {
  source      = "./values.yaml"  # Local path on your Windows machine
  destination = "/home/ubuntu/values.yaml"     # Destination on the remote machine
}  
  

  provisioner "remote-exec" {
    inline = [
    # "export ARM_CLIENT_ID=${var.client_id}",
    # "export ARM_CLIENT_SECRET=${var.client_secret}",
    # "export ARM_TENANT_ID=${var.tenant_id}",
    # "export ARM_SUBSCRIPTION_ID=${var.subscription_id}",
    # "az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID",
    # "echo 'Setting subscription...'",
    # #"az account set --subscription $ARM_SUBSCRIPTION_ID",
    # "echo 'Current subscription:'",
    # "az account show",
    "sudo apt-get install dos2unix",
    "dos2unix /home/ubuntu/setup.sh",
    "chmod +x /home/ubuntu/setup.sh",
    "/home/ubuntu/setup.sh"
  ]
  }
  
}