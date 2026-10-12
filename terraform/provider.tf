# Credentials come from the environment, never from files in this repo:
#   PROXMOX_VE_ENDPOINT   e.g. https://<host>:8006/
#   PROXMOX_VE_API_TOKEN  e.g. terraform@pve!citadel=<secret>
# Both live in an untracked, 0600 env file on the brain.
provider "proxmox" {
  insecure = var.proxmox_insecure_tls # host uses a self-signed cert; pin it once a CA cert is in place
}
