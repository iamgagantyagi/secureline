# main.tf

# Configure the Azure provider with service principal authentication
provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  
  features {}
}

data "azurerm_resource_group" "existing_rg" {
  name = var.resource_group_name
}

# Create a new Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = var.network_security_group
  location            = var.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name

  # SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTP access
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTPS access
  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
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
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create a public IP address
resource "azurerm_public_ip" "publicip" {
  name                = "${var.vm_name}-publicip"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create a network interface
resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
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
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.existing_rg.name
  user_data             = base64encode(templatefile("${path.module}/userdata.sh.tpl", { public_ip = azurerm_public_ip.publicip.ip_address }))
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                  = var.vm_size

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 70
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

  # Removing the managed identity section
  
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

# Create DNS zone if needed
resource "azurerm_dns_zone" "dns_zone" {
  count               = var.create_dns_zone ? 1 : 0
  name                = var.dns_zone
  resource_group_name = data.azurerm_resource_group.existing_rg.name
}

# Reference existing DNS zone if not creating a new one
data "azurerm_dns_zone" "existing_domain" {
  count               = var.create_dns_zone ? 0 : 1
  name                = var.dns_zone
  resource_group_name = data.azurerm_resource_group.existing_rg.name
}

# Create DNS A record using the public IP address
resource "azurerm_dns_a_record" "devops_org" {
  name                = var.dns_record_name
  zone_name           = var.create_dns_zone ? azurerm_dns_zone.dns_zone[0].name : data.azurerm_dns_zone.existing_domain[0].name
  resource_group_name = data.azurerm_resource_group.existing_rg.name
  ttl                 = 300
  records             = [azurerm_public_ip.publicip.ip_address]
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
    source      = "./setup.sh"
    destination = "/home/ubuntu/setup.sh"
  }
  
  provisioner "file" {
    source      = "./sonarqubevalues.yaml"
    destination = "/home/ubuntu/sonarqubevalues.yaml"
  }
  
  provisioner "file" { 
    source      = "./docker-compose.yml"
    destination = "/home/ubuntu/docker-compose.yml"
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo 'Copying files to remote host...'",
      "ls -l /home/ubuntu/",
      "echo 'Files copied successfully.'",
      "sudo apt-get install dos2unix",
      "dos2unix /home/ubuntu/sonarqubevalues.yaml",
      "dos2unix /home/ubuntu/docker-compose.yml",
      "export PUBLIC_IP=${azurerm_public_ip.publicip.ip_address}",
      "export CLIENT_ID=${var.client_id}",
      "export CLIENT_SECRET=${var.client_secret}",
      "export TENANT_ID=${var.tenant_id}",
      "export SUBSCRIPTION_ID=${var.subscription_id}",
      "chmod +x /home/ubuntu/setup.sh",
      "dos2unix /home/ubuntu/setup.sh",
      "/home/ubuntu/setup.sh"
    ]
  }
}