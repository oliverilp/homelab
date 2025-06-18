terraform {
  required_version = ">= 1.12.0"

  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.2-rc01"
    }
  }
}

variable "pm_api_url" {
  description = "Proxmox API URL"
  type = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type      = string
  sensitive = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type      = string
  sensitive = true
}

variable "public_ssh_key" {
  description = "Public SSH key for VM access"
  type      = string
  sensitive = true
}

variable "cloud_init_password" {
  description = "Cloud-init user password"
  type      = string
  sensitive = true
}

provider "proxmox" {
  pm_api_url = var.pm_api_url
  pm_api_token_id = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret

  pm_tls_insecure = false
}
