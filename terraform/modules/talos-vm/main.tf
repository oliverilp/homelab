terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

resource "proxmox_vm_qemu" "vm" {
  target_node = var.target_node
  description = "Kubernetes VM"
  agent = 1
  automatic_reboot = false
  vm_state = var.vm_state
  os_type = "cloud-init"
  clone = "talos-v1.13.5"
  scsihw = "virtio-scsi-single"
  # boot = "order=scsi0;ide2;net0"
  onboot = var.onboot
  
  nameserver = "1.1.1.1 8.8.8.8"
  skip_ipv6 = true
  
  cpu {
    cores = var.cpu_cores
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
    tag = var.network_tag
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "${var.target_node}-nvme"
          size = var.disk_size
        }
      }
      dynamic "scsi1" {
        for_each = var.ceph_disk_size > 0 ? [1] : []
        content {
          disk {
            storage = "${var.target_node}-nvme"
            size    = var.ceph_disk_size
          }
        }
      }
    }
    ide {
      ide2 {
        cdrom {
          iso = "truenas-nfs:iso/nocloud-amd64-qemu-guest-agent-v1.11.2.iso"
        }
      }
      ide3 {
        cloudinit {
          storage = "${var.target_node}-nvme"
        }
      }
    }
  }
  
  count = var.vm_count
  vmid = var.vmid
  name = "${var.name_prefix}-0${var.ip_offset}"
  memory = var.memory
  balloon = var.balloon
  ipconfig0 = "ip=${var.ip_base}${count.index + var.ip_offset}/24,gw=${var.gateway}"
}
