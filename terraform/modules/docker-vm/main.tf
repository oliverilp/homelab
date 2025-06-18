terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.2-rc01"
    }
  }
}

resource "proxmox_vm_qemu" "vm" {
  target_node = "ramiel"
  desc = "Docker VM"
  agent = 0
  automatic_reboot = false
  vm_state = var.vm_state
  os_type = "cloud-init"
  clone = "ubuntu-cloud-noble"
  scsihw = "virtio-scsi-single"
  boot = "order=scsi0"
  onboot = true
  
  nameserver = "1.1.1.1 8.8.8.8"
  skip_ipv6 = true
  ciupgrade = true
  ciuser = "ubuntu"
  
  cpu {
    cores = 4
    type = "host"
  }

  vga {
    type   = "std"
  }
  
  network {
    id = 0
    bridge = "vmbr0"
    model = "virtio"
    link_down = false
  }
  
  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-zfs"
          size = var.disk_size
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-zfs"
        }
      }
    }
  }
  
  vmid = var.vmid
  name = var.name
  memory = var.memory
  balloon = var.balloon
  ipconfig0 = "ip=${var.ip}/24,gw=10.1.1.1"
  cipassword = var.cloud_init_password
  sshkeys = var.public_ssh_key
}
