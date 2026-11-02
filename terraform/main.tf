locals {
  tags = var.tags
}

resource "azurerm_resource_group" "target" {
  name     = var.resource_group_name
  location = data.azurerm_virtual_network.target.location
  tags     = local.tags
}

data "azurerm_key_vault" "global" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "admin_password" {
  name         = var.key_vault_secret_name
  key_vault_id = data.azurerm_key_vault.global.id
  version      = var.key_vault_secret_version
}

data "azurerm_virtual_network" "target" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

data "azurerm_subnet" "target" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.target.name
  resource_group_name  = var.virtual_network_resource_group_name
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.target.location
  resource_group_name = azurerm_resource_group.target.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.target.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = var.vm_name
  computer_name                   = var.vm_name
  location                        = azurerm_resource_group.target.location
  resource_group_name             = azurerm_resource_group.target.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = data.azurerm_key_vault_secret.admin_password.value
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.vm.id]
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  plan {
    publisher = var.image_publisher
    product   = var.image_offer
    name      = var.image_sku
  }
}

resource "azapi_update_resource" "os_disk_tags" {
  type        = "Microsoft.Compute/disks@2023-04-02"
  resource_id = azurerm_linux_virtual_machine.vm.os_disk[0].id

  body = {
    tags = local.tags
  }
}
