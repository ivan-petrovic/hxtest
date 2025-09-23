variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-hylastix"
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_prefix" {
  description = "Subnet prefix"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "vm-hylastix-01"
}

variable "vm_size" {
  description = "Size of the VM"
  type        = string
  default     = "Standard_B1ms"
  # default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key to inject into the VM (openssh format)"
  type        = string
}
