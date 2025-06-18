variable "vmid" {
  description = "VM ID"
  type        = string
}

variable "name" {
  description = "Name for VM"
  type        = string
}

variable "vm_state" {
  description = "VM state (running, stopped, etc.)"
  type        = string
  default     = "running"
}

variable "memory" {
  description = "Memory in MB (maximum when using ballooning)"
  type        = number
}

variable "balloon" {
  description = "Minimum memory in MB for ballooning"
  type        = number
  default     = 0
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
}

variable "ip" {
  description = "IP address (e.g., '10.1.1.3' for 10.1.1.31, 10.1.1.32, etc.)"
  type        = string
}

variable "cloud_init_password" {
  description = "Cloud-init user password"
  type        = string
  sensitive   = true
}

variable "public_ssh_key" {
  description = "Public SSH key for VM access"
  type        = string
  sensitive   = true
}
