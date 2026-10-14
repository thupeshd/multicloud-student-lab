resource "azurerm_resource_group" "lab" {
  name     = "${var.name}-rg"
  location = var.azure_location
  tags     = local.tags
}
resource "azurerm_virtual_network" "lab" {
  name                = "${var.name}-vnet"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.20.0.0/16"]
}
resource "azurerm_subnet" "lab" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.1.0/24"]
}
resource "azurerm_public_ip" "lab" {
  name                = "${var.name}-ip"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_network_security_group" "lab" {
  name                = "${var.name}-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  security_rule {
    name                       = "http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "admin-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "metrics"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9100"
    source_address_prefix      = "${google_compute_address.lab.address}/32"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_interface" "lab" {
  name                = "${var.name}-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  ip_configuration {
    name                          = "app"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab.id
  }
}
resource "azurerm_network_interface_security_group_association" "lab" {
  network_interface_id      = azurerm_network_interface.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}
resource "azurerm_linux_virtual_machine" "lab" {
  name                            = "${var.name}-azure"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.azure_vm_size
  admin_username                  = "labadmin"
  network_interface_ids           = [azurerm_network_interface.lab.id]
  disable_password_authentication = true
  admin_ssh_key {
    username   = "labadmin"
    public_key = local.ssh_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(local.app_azure)
  tags        = local.tags
  depends_on  = [azurerm_network_interface_security_group_association.lab]
}
resource "azurerm_traffic_manager_profile" "lab" {
  name                   = "${var.name}-dns"
  resource_group_name    = azurerm_resource_group.lab.name
  traffic_routing_method = var.routing_method
  dns_config {
    relative_name = var.name
    ttl           = 30
  }
  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
  tags = local.tags
}
resource "azurerm_traffic_manager_external_endpoint" "lab" {
  for_each = {
    aws   = { ip = aws_eip.lab.public_ip, priority = 1 }
    azure = { ip = azurerm_public_ip.lab.ip_address, priority = 2 }
    gcp   = { ip = google_compute_address.lab.address, priority = 3 }
  }
  name       = each.key
  profile_id = azurerm_traffic_manager_profile.lab.id
  target     = each.value.ip
  priority   = each.value.priority
  weight     = 1
}
