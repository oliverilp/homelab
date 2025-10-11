locals {
  master_defaults = {
    vmid_prefix     = "40"
    name_prefix     = "k8s-master"
    vm_state        = "running"
    cpu_cores       = 4
    memory          = 6144
    disk_size       = 20
    ip_base         = "10.1.1.3"
    onboot          = true
    balloon         = 0
  }
  
  worker_defaults = {
    vmid_prefix     = "41"
    name_prefix     = "k8s-worker"
    vm_state        = "running"
    cpu_cores       = 6
    memory          = 15360
    balloon         = 10240
    disk_size       = 500
    ip_base         = "10.1.1.4"
    onboot          = false
  }
  
  vms = {
    "master-01" = merge(local.master_defaults, {
      target_node     = "ramiel"
      ip_offset       = 1
      storage_offset  = 0
    })
    "master-02" = merge(local.master_defaults, {
      target_node     = "casper"
      ip_offset       = 2
      storage_offset  = 0
    })
    "master-03" = merge(local.master_defaults, {
      target_node     = "ramiel"
      ip_offset       = 3
      storage_offset  = 1
    })
    "worker-01" = merge(local.worker_defaults, {
      target_node     = "ramiel"
      ip_offset       = 1
      storage_offset  = 2
    })
    "worker-02" = merge(local.worker_defaults, {
      target_node     = "casper"
      ip_offset       = 2
      storage_offset  = 0
    })
    "worker-03" = merge(local.worker_defaults, {
      target_node     = "ramiel"
      ip_offset       = 3
      storage_offset  = 0
    })
  }
}
module "k8s_vms" {
  source = "./modules/talos-vm"
  
  for_each = local.vms
  
  target_node     = each.value.target_node
  vmid_prefix     = each.value.vmid_prefix
  name_prefix     = each.value.name_prefix
  vm_state        = each.value.vm_state
  cpu_cores       = each.value.cpu_cores
  memory          = each.value.memory
  balloon         = each.value.balloon
  disk_size       = each.value.disk_size
  ip_base         = each.value.ip_base
  ip_offset       = each.value.ip_offset
  onboot          = each.value.onboot
  storage_offset  = each.value.storage_offset
  vm_count        = 1
}
