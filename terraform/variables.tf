variable "resource_group_name" {
  description = "Resource group to create for the VM and NIC."
  type        = string
  default     = "rsg-inventree-prod"
}

variable "tags" {
  description = "Tags applied to the resource group, VM, NIC, and managed OS disk."
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Application = "InvenTree"
    Server      = "INAZEUWS012"
  }
}

variable "virtual_network_name" {
  description = "Existing virtual network containing the target subnet."
  type        = string
  default     = "vnet-Intero-WestEU-Prod"
}

variable "virtual_network_resource_group_name" {
  description = "Resource group containing the existing virtual network and subnet."
  type        = string
  default     = "rsg-Intero-Europe-Prod"
}

variable "subnet_name" {
  description = "Existing subnet to attach the VM to."
  type        = string
  default     = "BackendSubnetWestEU"
}

variable "vm_name" {
  description = "Azure VM and guest computer name."
  type        = string
  default     = "INAZEUWS012"
}

variable "private_ip_address" {
  description = "Static private IPv4 address. It must be available in the selected subnet."
  type        = string
  default     = "10.52.1.93"
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_B2als_v2"
}

variable "os_disk_size_gb" {
  description = "Managed OS disk size in GiB."
  type        = number
  default     = 64

  validation {
    condition     = var.os_disk_size_gb >= 64
    error_message = "The OS disk must be at least 64 GiB."
  }
}

variable "admin_username" {
  description = "Non-root administrator account provisioned on the VM."
  type        = string
  default     = "interoadmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the administrator account; provide it through TF_VAR_admin_ssh_public_key or a private tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.admin_ssh_public_key)) > 0
    error_message = "Provide an SSH public key for the administrator account."
  }
}

variable "key_vault_name" {
  description = "Name of the existing Azure Key Vault containing the administrator password."
  type        = string
  default     = "kv-intero-global"
}

variable "key_vault_resource_group_name" {
  description = "Resource group containing the Azure Key Vault."
  type        = string
  default     = "rsg-kv-intero_global"
}

variable "key_vault_secret_name" {
  description = "Name of the Key Vault secret used as the VM administrator password."
  type        = string
  default     = "interoAdmin"
}

variable "key_vault_secret_version" {
  description = "Pinned version of the Key Vault administrator-password secret."
  type        = string
  default     = "81633b8071014500a5ee6a7a884bc2a8"
}

variable "image_publisher" {
  description = "Publisher identifier for the selected FreeBSD Azure Marketplace image and its Marketplace plan."
  type        = string
}

variable "image_offer" {
  description = "Offer identifier for the selected FreeBSD Azure Marketplace image and Marketplace plan product."
  type        = string
}

variable "image_sku" {
  description = "SKU identifier for the selected FreeBSD Azure Marketplace image and Marketplace plan name."
  type        = string
}

variable "image_version" {
  description = "Version of the selected FreeBSD Marketplace image."
  type        = string
  default     = "latest"
}
