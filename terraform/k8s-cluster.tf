locals {
  master_defaults = {
    vmid_prefix     = "40"
    name_prefix     = "k8s-master"
    cpu_cores       = 4
    memory          = 8192
    disk_size       = 20
    gateway         = "10.1.20.1"
    ip_base         = "10.1.20.1"
    network_tag     = 20
    onboot          = true
    balloon         = 0
  }
  
  worker_defaults = {
    vmid_prefix     = "41"
    name_prefix     = "k8s-worker"
    cpu_cores       = 6
    memory          = 20480
    balloon         = 15360
    disk_size       = 500
    gateway         = "10.1.20.1"
    ip_base         = "10.1.20.2"
    network_tag     = 20
    onboot          = false
  }
  
  vms = {
    "master-01" = merge(local.master_defaults, {
      target_node     = "melchior"
      ip_offset       = 1
      storage_offset  = 0
      vmid            = 401
    })
    "master-02" = merge(local.master_defaults, {
      target_node     = "casper"
      ip_offset       = 2
      storage_offset  = 0
      vmid            = 402
    })
    "master-03" = merge(local.master_defaults, {
      target_node     = "balthasar"
      ip_offset       = 3
      storage_offset  = 0
      vmid            = 403
    })
    "worker-01" = merge(local.worker_defaults, {
      target_node     = "melchior"
      ip_offset       = 1
      storage_offset  = 0
      vmid            = 411
      cpu_cores       = 4
    })
    "worker-02" = merge(local.worker_defaults, {
      target_node     = "casper"
      ip_offset       = 2
      storage_offset  = 0
      vmid            = 412
    })
    "worker-03" = merge(local.worker_defaults, {
      target_node     = "balthasar"
      ip_offset       = 3
      storage_offset  = 0
      vmid            = 413
    })
  }
}
module "k8s_vms" {
  source = "./modules/talos-vm"

  for_each = local.vms

  target_node     = each.value.target_node
  vmid_prefix     = each.value.vmid_prefix
  name_prefix     = each.value.name_prefix
  cpu_cores       = each.value.cpu_cores
  memory          = each.value.memory
  balloon         = each.value.balloon
  disk_size       = each.value.disk_size
  gateway         = each.value.gateway
  ip_base         = each.value.ip_base
  ip_offset       = each.value.ip_offset
  network_tag     = each.value.network_tag
  onboot          = each.value.onboot
  storage_offset  = each.value.storage_offset
  vmid            = each.value.vmid
  vm_count        = 1
}
