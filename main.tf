#CRIANDO E PREPARANDO AMBIENTE DO TERRAFORM ===== Azure OK
terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.25"
    }
  }
}

#PROVIDER SERVER PARA NÃO FICAR PEDINDO LOGIN 
provider "azurerm" {
  skip_provider_registration = true
  features {}
}

#CRIANDO RESOURCE GROUP NO AZURE / rg = RESOURCE GROUP
resource "azurerm_resource_group" "rg-aulainfra" {
    name     = "terraform_mv"
    location = "eastus"      
}
#ATE AQUI A VERSÃO DO TERRAFORM FICOU PRONTA
##################################################################


#CRIANDO UMA REDE VIRTUAL / vnet = VIRTUAL NETWORK ==== Azure OK
resource "azurerm_virtual_network" "vnet-aulainfra" {
  name                = "vnetaula"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
  address_space       = ["10.0.0.0/16"]       
}
##################################################################


#CRIANDO UMA SUB REDE VIRTUAL / subnet = SUB NETWORK
resource "azurerm_subnet" "subnet-aulainfra" {
  name                 = "subnetaula"
  resource_group_name  = azurerm_resource_group.rg-aulainfra.name
  virtual_network_name = azurerm_virtual_network.vnet-aulainfra.name
  address_prefixes       = ["10.0.1.0/24"]
}
##################################################################


#CRIANDO IP PUBLICO / public = PUBLICO
resource "azurerm_public_ip" "publicip-aulainfra" {
  name                         = "public-aulainfra"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name
  allocation_method            = "Static"
}
##################################################################


#CRIANDO NETWORK SECURITY GROUP PORTA 22 USADO PELO SSH / nsg = NETWORK SECURITY GROUP
resource "azurerm_network_security_group" "nsg-aulainfra" {
  name                = "nsgaula"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

    security_rule {
    name                       = "apache"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
##################################################################


#CRIANDO UMA PLACA DE REDE / ni = NETWORK INTERFACE
resource "azurerm_network_interface" "ni-aulainfra" {
  name                = "niaula"
  location            = azurerm_resource_group.rg-aulainfra.location
  resource_group_name = azurerm_resource_group.rg-aulainfra.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet-aulainfra.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip-aulainfra.id
  }
}

resource "azurerm_network_interface_security_group_association" "example" {
  network_interface_id      = azurerm_network_interface.ni-aulainfra.id
  network_security_group_id = azurerm_network_security_group.nsg-aulainfra.id
}
##################################################################


#CRIANDO MAQUINA VIRTUAL / vm = VIRTUAL MACHINE
resource "azurerm_linux_virtual_machine" "vm-aulainfra" {
  name                  = "vmaula"
  location              = azurerm_resource_group.rg-aulainfra.location
  resource_group_name   = azurerm_resource_group.rg-aulainfra.name
  size                  = "Standard_DS2_v2"
  admin_username        = var.user
  admin_password        = var.password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.ni-aulainfra.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  depends_on = [
    azurerm_resource_group.rg-aulainfra,
    azurerm_network_interface.ni-aulainfra
  ]
}
##################################################################
#EFETUAR IMPORTAÇÃO aulainfra-fS ELEMENTO CRIADO FORA DO TERRAFORM DENTRO DO AZURE
#resource "azurerm_resource_group" "rg-aulainfra2" {
#    name     = "aulainfra-fs"
#    location = "eastus"
#}
####### DEMONSTRAÇÃO #######
##################################################################

#IDENTIFICAR IP DA MAQUINA
output "public_ip" {
  value = azurerm_public_ip.publicip-aulainfra.ip_address
}


resource "null_resource" "upload-script" {
  provisioner "file" {
    connection {
      type = "ssh"
      user = var.user
      password = var.password
      host = azurerm_public_ip.publicip-aulainfra.ip_address
    }
    source = "script"
    destination = "/home/adminuser"
  }
}


resource "null_resource" "exec-script" {
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = var.user
      password = var.password
      host = azurerm_public_ip.publicip-aulainfra.ip_address
    }
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/adminuser/mysql/script/user.sql",
      "sudo mysql < /home/adminuser/mysql/script/schema.sql",
      "sudo mysql < /home/adminuser/mysql/script/data.sql",
      "sudo mysql < /home/adminuser/config/mysql.cnf /etc/mysql.conf.d/mysql.cnf",
      "sudo service mysql restart",
      "sleep 20"
    ] 
  }
}

