# Fleet containers under Terraform management.
#
# SCOPE: CT110 (brain) and CT113 (news-briefing) only.
# CT111 (trading-workload) is production and is deliberately NOT declared here;
# it will be adopted last, on explicit go (docs/portfolio-plan.md, Phase 6).
#
# These resources were written to match live state and imported (see imports.tf).
# `terraform plan` must show NO changes before anything is ever applied.
#
# Not manageable via the provider (stay in playbooks/host-tun-passthrough.sh):
#   lxc.cgroup2.devices.allow / lxc.mount.entry (TUN device for Tailscale)
# `ignore_changes` on disk/initialization keeps Terraform from touching fields
# that are fixed at creation time.

resource "proxmox_virtual_environment_container" "claude_brain" {
  node_name     = var.node_name
  vm_id         = 110
  unprivileged  = true
  start_on_boot = false # TODO confirm against live `onboot` during first plan

  description = "Claude orchestration brain (hub of the hub-and-spoke SSH model)"

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 20
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "claude-brain"
    dns {
      servers = ["1.1.1.1"]
    }
    ip_config {
      ipv4 {
        address = "192.0.2.30/24"
        gateway = "192.0.2.1"
      }
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = true
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [operating_system, disk, initialization[0].user_account]
  }
}

resource "proxmox_virtual_environment_container" "news_briefing" {
  node_name     = var.node_name
  vm_id         = 113
  unprivileged  = true
  start_on_boot = false # TODO confirm against live `onboot` during first plan

  description = "Daily news briefing (lowest-priority workload: cpuunits 512)"

  cpu {
    cores = 1
    units = 512
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 10
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "news-briefing"
    dns {
      servers = ["1.1.1.1"]
    }
    ip_config {
      ipv4 {
        address = "192.0.2.33/24"
        gateway = "192.0.2.1"
      }
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [operating_system, disk, initialization[0].user_account]
  }
}
