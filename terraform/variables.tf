variable "node_name" {
  description = "Proxmox node that hosts the fleet"
  type        = string
  default     = "proxmox"
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (self-signed host cert)"
  type        = bool
  default     = true
}

variable "template_file_id" {
  description = "Placeholder only: the OS template is fixed at creation and ignored via lifecycle.ignore_changes. Needed solely to satisfy the provider schema for imported containers."
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
