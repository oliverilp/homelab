module "docker" {
  source = "./modules/docker-vm"
  
  vmid = "210"
  name = "tailkeep-docker"
  vm_state    = "running"
  memory      = 4096
  disk_size   = 30
  ip          = "10.1.1.25"
  
  cloud_init_password = var.cloud_init_password
  public_ssh_key = var.public_ssh_key
}
