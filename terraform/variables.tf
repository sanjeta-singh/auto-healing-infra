variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group"
}

variable "resource_group_location" {
  type        = string
  description = "Location of the Resource Group"
}

variable "vnet_cidr_address_space" {
  type        = list(string)
  description = "CIDR block for the Virtual Network"
}

variable "vnet_cidr_name" {
  type        = string
  description = "Name of the Virtual Network"
}

variable "subnet_name" {
  type        = string
  description = "Name of the Subnet"
}

variable "subnet_address_space" {
  type        = list(string)
  description = "CIDR block for the Subnet"
}

variable "network_interface_name" {
  type        = string
  description = "Name of the Network Interface"
}

variable "public_ip_name" {
  type        = string
  description = "Name of the Public IP"
}

variable "network_security_group_name" {
  type        = string
  description = "Name of the Network Security Group"
}

variable "vm_name" {
  type        = string
  description = "The name of the Virtual Machine in Azure"
}

variable "vm_size" {
  type        = string
  description = "Size of the Virtual Machine"
}

variable "admin_username_vm" {
  type        = string
  description = "Admin username for the Virtual Machine"
}

variable "computer_name" {
  type        = string
  description = "Computer name for the Virtual Machine"
}
