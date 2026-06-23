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
  default     = "started"
}

variable "cpu_cores" {
  description = "Number of CPU cores to allocate to each VM"
  type        = number
  default     = 4
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
  description = "Base IP address (e.g., '10.1.20.1' for 10.1.20.11, 10.1.20.12, etc.)"
  type        = string
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
  
  validation {
    condition     = var.vm_count <= 3
    error_message = "vm_count cannot exceed 3 due to NVME storage limitations (nvme0, nvme1, nvme2)."
  }
}

variable "ip_offset" {
  description = "IP offset for numbering (e.g., 1 for .31, .32, etc.)"
  type        = number
  default     = 1
}

variable "onboot" {
  description = "Whether the VM should start on boot"
  type        = bool
  default     = true
}

variable "storage_offset" {
  description = "Storage offset for NVME naming to avoid conflicts between modules (e.g., 0 for nvme0, 3 for nvme3)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.storage_offset >= 0 && var.storage_offset <= 2
    error_message = "storage_offset must be between 0 and 2 to match available NVME drives (nvme0, nvme1, nvme2)."
  }
}

variable "target_node" {
  description = "Proxmox node hostname where the VM should be created"
  type        = string
  default     = "melchior"
}

variable "vmid" {
  description = "Specific VM ID to use (overrides vmid_prefix calculation)"
  type        = number
  default     = null
}

variable "network_tag" {
  description = "VLAN tag for the network interface"
  type        = number
  default     = 1
}

variable "gateway" {
  description = "Gateway IP address for the network"
  type        = string
  default     = "10.1.1.1"
}

variable "ceph_disk_size" {
  description = "Size of the Ceph OSD disk in GB (0 = no Ceph disk)"
  type        = number
  default     = 0
}
