module "k8s_master" {
  source = "./modules/talos-vm"
  
  vm_count = 3
  vmid_prefix = "40"
  name_prefix = "k8s-master"
  vm_state    = "running"
  memory      = 4096
  disk_size   = 20
  ip_base     = "10.1.1.3"
  ip_offset   = 1
}

module "k8s_worker" {
  source = "./modules/talos-vm"
  
  vm_count = 2
  vmid_prefix = "41"
  name_prefix = "k8s-worker"
  vm_state    = "running"
  memory      = 8192
  balloon     = 4096
  disk_size   = 30
  ip_base     = "10.1.1.4"
  ip_offset   = 1
}
