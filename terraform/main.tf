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
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

###########################################################
## 1. DATA SOURCES, AUTOMATED PACKAGING & LOCAL BUILDS
###########################################################

resource "null_resource" "pip_install" {
  triggers = {
    requirements_hash = filemd5("${path.module}/../automation-function/requirements.txt")
  }
  provisioner "local-exec" {
    command = "pip3 install -r ${path.module}/../automation-function/requirements.txt --target=\"${path.module}/../automation-function/.python_packages/lib/site-packages\""
  }
}

data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../automation-function"
  output_path = "${path.module}/function.zip"
  excludes    = [".venv", "venv", "__pycache__", "function.zip"]
  depends_on  = [null_resource.pip_install]
}

###########################################################
## 2. RESOURCES GROUP & NETWORKING
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

  security_rule {
    name                       = "AllowFlask"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
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

  network_interface_ids = [azurerm_network_interface.nic.id]

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
## 3. AUTOMATION & MONITORING INFRASTRUCTURE
###########################################################

resource "random_integer" "storage_id" {
  min = 10000
  max = 99999
}

resource "azurerm_storage_account" "func_storage" {
  name                     = "healfuncstorage${random_integer.storage_id.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "func_plan" {
  name                = "autoheal-app-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "S1"
}

resource "azurerm_log_analytics_workspace" "workspace" {
  name                = "autoheal-log-workspace"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "app_insights" {
  name                = "${var.function_app_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.workspace.id
  application_type    = "web"
}

resource "azurerm_linux_function_app" "heal_func" {
  name                       = "${var.function_app_name}-${random_integer.storage_id.result}"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  service_plan_id            = azurerm_service_plan.func_plan.id
  storage_account_name       = azurerm_storage_account.func_storage.name
  storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key
  zip_deploy_file            = data.archive_file.function_zip.output_path

  site_config {
    always_on = true
    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.app_insights.connection_string
    "FUNCTIONS_WORKER_RUNTIME"              = "python"
    "AzureWebJobsFeatureFlags"              = "EnableWorkerIndexing"
    "AzureWebJobsStorage"                   = azurerm_storage_account.func_storage.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    "TARGET_VM_NAME"                        = azurerm_linux_virtual_machine.vm.name
    "TARGET_RESOURCE_GROUP"                 = azurerm_resource_group.rg.name
    "TARGET_SUBSCRIPTION_ID"                = "5dd09e90-5d01-4fe1-aa6d-3f17def1c0f8"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "vm_group_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_function_app.heal_func.identity[0].principal_id
}

###########################################################
## 5. LIVE OBSERVABILITY LOOP & WEBHOOKS
###########################################################

data "azurerm_function_app_host_keys" "func_keys" {
  name                = azurerm_linux_function_app.heal_func.name
  resource_group_name = azurerm_resource_group.rg.name
  depends_on          = [azurerm_linux_function_app.heal_func]
}

resource "azurerm_monitor_action_group" "remediation_ag" {
  name                = "remediation-action-group"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "AutoHealAG"

  webhook_receiver {
    name                    = "TriggerHealerFunction"
    service_uri             = "https://${azurerm_linux_function_app.heal_func.default_hostname}/api/remediation_trigger?code=${data.azurerm_function_app_host_keys.func_keys.default_function_key}"
    use_common_alert_schema = true
  }
}

resource "azurerm_application_insights_web_test" "flask_health_check" {
  name                    = "flask-app-health-test"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.app_insights.id
  kind                    = "ping"
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  geo_locations           = ["apac-sg-sin-azr", "us-va-ash-azr"]

  configuration = <<XML
<WebTest Name="flask-app-health-test" Id="A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D" Enabled="True" CatalogClassName="" CatalogDisplayName="" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Items>
    <Request Method="GET" Guid="B2C3D4E5-F6A7-8B9C-0D1E-2F3A4B5C6D7E" Version="1.1" Url="http://${azurerm_public_ip.pip.ip_address}/health" ThinkTime="0" Timeout="30" ParseDependentRequests="False" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" AcceptLanguage="" Accept="" Headers="" Body="" />
  </Items>
</WebTest>
XML
}

resource "azurerm_monitor_metric_alert" "app_insights_alert" {
  name                = "flask-app-down-alert"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_application_insights.app_insights.id]
  window_size         = "PT5M"
  frequency           = "PT1M"
  severity            = 1
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.remediation_ag.id
  }
}