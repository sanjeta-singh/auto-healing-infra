terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "azurerm" {
  features {}
}

# ~> means increament the rightmost number only for eg in 3.0.2 only the last rightmost number 2 can be changed like 3.0.10 but never 3.1.0

###########################################################
## 1. DATA SOURCES & PACKAGING
###########################################################

# Automatically packages local Python code into a deployment zip
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../automation-function"
  output_path = "${path.module}/function.zip"
}

###########################################################
##   2. resources group   ##
###########################################################

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_virtual_network" "vnet_dev" {
  name                = var.vnet_cidr_name
  address_space       = var.vnet_cidr_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "sub_dev" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_dev.name
  address_prefixes     = var.subnet_address_space
}

resource "azurerm_network_security_group" "nsg" {
  name                = var.network_security_group_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = var.network_interface_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub_dev.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = var.vm_name
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = var.vm_size
  admin_username                  = var.admin_username_vm
  computer_name                   = var.computer_name
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username_vm
    public_key = file("~/.ssh/id_rsa.pub")
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
}

###########################################################
## 3. AUTOMATION & MONITORING INFRASTRUCTURE (THE HUB)
###########################################################

resource "azurerm_resource_group" "rg_shared" {
  name     = var.shared_resource_group_name
  location = var.resource_group_location
}

resource "random_integer" "storage_id" {
  min = 10000
  max = 99999
}

resource "azurerm_storage_account" "func_storage" {
  name                     = "healfuncstorage${random_integer.storage_id.result}"
  resource_group_name      = azurerm_resource_group.rg_shared.name
  location                 = azurerm_resource_group.rg_shared.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func_plan" {
  name                = "autoheal-app-plan"
  resource_group_name = azurerm_resource_group.rg_shared.name
  location            = azurerm_resource_group.rg_shared.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "heal_func" {
  name                       = "${var.function_app_name}-${random_integer.storage_id.result}"
  resource_group_name        = azurerm_resource_group.rg_shared.name
  location                   = azurerm_resource_group.rg_shared.location
  service_plan_id            = azurerm_service_plan.func_plan.id
  storage_account_name       = azurerm_storage_account.func_storage.name
  storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key
  zip_deploy_file            = data.archive_file.function_zip.output_path

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

###########################################################
## 4. ROLE-BASED ACCESS CONTROL (IAM SECURITY BRIDGE)
###########################################################

# Assign role at the Parent Resource Group level so it inherits down to 100s of VMs seamlessly
resource "azurerm_role_assignment" "vm_group_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_function_app.heal_func.identity[0].principal_id
}

###########################################################
## 5. LIVE OBSERVABILITY LOOP & WEBHOOKS
###########################################################

# Intercepts and retrieves the internal app password/host key programmatically
data "azurerm_function_app_host_keys" "func_keys" {
  name                = azurerm_linux_function_app.heal_func.name
  resource_group_name = azurerm_resource_group.rg_shared.name
  depends_on          = [azurerm_linux_function_app.heal_func]
}

resource "azurerm_monitor_action_group" "remediation_ag" {
  name                = "remediation-action-group"
  resource_group_name = azurerm_resource_group.rg_shared.name
  short_name          = "AutoHealAG"

  webhook_receiver {
    name                    = "TriggerHealerFunction"
    service_uri             = "https://${azurerm_linux_function_app.heal_func.default_hostname}/api/remediation_trigger?code=${data.azurerm_function_app_host_keys.func_keys.default_function_key}"
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "network_drop_alert" {
  name                = "zero-inbound-traffic-alert"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  description         = "Triggers self-healing loop instantly when inbound connection metrics drop below 1."
  window_size         = "PT1M"
  frequency           = "PT1M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Inbound Flows"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.remediation_ag.id
  }
}