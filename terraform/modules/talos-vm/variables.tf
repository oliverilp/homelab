variable "vmid_prefix" {
  description = "Prefix for VM ID (e.g., '40' for 401, 402, etc.)"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for VM name (e.g., 'k8s-master' for k8s-master-01)"
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

variable "ip_base" {
  description = "Base IP address (e.g., '10.1.1.3' for 10.1.1.31, 10.1.1.32, etc.)"
  type        = string
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "ip_offset" {
  description = "IP offset for numbering (e.g., 1 for .31, .32, etc.)"
  type        = number
  default     = 1
}
