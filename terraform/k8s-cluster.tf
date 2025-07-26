module "k8s_master" {
  source = "./modules/talos-vm"
  
  vm_count = 3
  vmid_prefix = "40"
  name_prefix = "k8s-master"
  vm_state    = "running"
  memory      = 8192
  disk_size   = 20
  ip_base     = "10.1.1.3"
  ip_offset   = 1
  onboot      = true
  storage_offset = 0  # Uses nvme0, nvme1, nvme2
}

module "k8s_worker" {
  source = "./modules/talos-vm"
  
  vm_count = 3
  vmid_prefix = "41"
  name_prefix = "k8s-worker"
  vm_state    = "running"
  memory      = 20480
  balloon     = 10240
  disk_size   = 500
  ip_base     = "10.1.1.4"
  ip_offset   = 1
  onboot      = false
  storage_offset = 0  # Uses nvme0, nvme1, nvme2 (cycling with masters)
}
