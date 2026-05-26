variable "resource_group_name" {
  type    = string
  default = "auto-healing-rg"
}

variable "resource_group_location" {
  type    = string
  default = "Central India"
}

variable "vnet_cidr_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/24"]
  description = "CIDR block for the Virtual Network"
}

variable "vnet_cidr_name" {
  type        = string
  default     = "autoheal-vnet"
  description = "Name of the Virtual Network"
}

variable "subnet_name" {
  type        = string
  default     = "autoheal-subnet"
  description = "Name of the Subnet"
}

variable "subnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/25"]
  description = "CIDR block for the Subnet"
}

variable "network_interface_name" {
  type        = string
  default     = "autoheal-nic"
  description = "Name of the Network Interface"
}

variable "public_ip_name" {
  type        = string
  default     = "autoheal-ip"
  description = "Name of the Public IP"
}

variable "network_security_group_name" {
  type    = string
  default = "autoheal-nsg"
}

variable "vm_name" {
  type        = string
  default     = "autoheal"
  description = "The name of the Virtual Machine in Azure"
}

variable "vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Size of the Virtual Machine"
}

variable "admin_username_vm" {
  type        = string
  default     = "sanjeta"
  description = "Admin username for the Virtual Machine"
}

variable "computer_name" {
  type    = string
  default = "autoheal"
}
