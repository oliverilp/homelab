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
  desc = "Kubernetes VM"
  agent = 1
  automatic_reboot = false
  vm_state = var.vm_state
  os_type = "cloud-init"
  clone = "talos-v1.10.4"
  scsihw = "virtio-scsi-single"
  # boot = "order=scsi0;ide2;net0"
  onboot = true
  
  nameserver = "1.1.1.1 8.8.8.8"
  skip_ipv6 = true
  
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
        cdrom {
          iso = "local:iso/nocloud-amd64-qemu-guest-agent-longhorn-compatible.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "local-zfs"
        }
      }
    }
  }
  
  count = var.vm_count
  vmid = "${var.vmid_prefix}${count.index + 1}"
  name = "${var.name_prefix}-0${count.index + 1}"
  memory = var.memory
  ipconfig0 = "ip=${var.ip_base}${count.index + var.ip_offset}/24,gw=10.1.1.1"
}
