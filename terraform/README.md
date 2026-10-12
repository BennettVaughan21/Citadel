# Terraform — fleet definitions

Manages **CT110 (brain)** and **CT113 (news-briefing)** by importing live state. **CT111 (trading-workload) is intentionally absent** — production, adopted last on explicit go.

## One-time setup (host admin, run on the Proxmox host as root)

Stage 1 is a **read-only** token, enough for `terraform plan` against imported state. It is ACL-scoped to CT110/CT113 only, so it cannot see or touch CT111.

```bash
pveum role add CitadelAudit -privs "VM.Audit Sys.Audit Datastore.Audit"
pveum user add terraform@pve --comment "citadel terraform (read-only stage)"
pveum user token add terraform@pve citadel --privsep 1      # prints the secret ONCE
pveum acl modify /vms/110 --tokens 'terraform@pve!citadel' --roles CitadelAudit
pveum acl modify /vms/113 --tokens 'terraform@pve!citadel' --roles CitadelAudit
pveum acl modify /nodes/proxmox --tokens 'terraform@pve!citadel' --roles CitadelAudit
pveum acl modify /storage --tokens 'terraform@pve!citadel' --roles CitadelAudit
```

If `plan` reports permission errors, widen the audit ACL — don't add write roles. Write privileges (a second role, applied only after a reviewed clean plan) are a separate approval.

On the **brain**, store credentials in an untracked 0600 file and never commit it:

```bash
umask 077
cat > ~/.config/citadel-terraform.env <<'ENV'
PROXMOX_VE_ENDPOINT=https://192.0.2.23:8006/
PROXMOX_VE_API_TOKEN=terraform@pve!citadel=<secret>
ENV
```

## Use

```bash
set -a; . ~/.config/citadel-terraform.env; set +a
terraform init
terraform plan        # must show: imports only, no changes, no destroys
```

State stays local on the brain (`*.tfstate` is gitignored, and it is covered by the nightly CT110 backup). `prevent_destroy` is set on every container.

## What Terraform cannot manage here

The provider has no support for raw `lxc.*` keys, so the TUN passthrough (`lxc.cgroup2.devices.allow`, `lxc.mount.entry`) that Tailscale needs stays in `playbooks/host-tun-passthrough.sh`. Terraform describes the container; that script finishes the host-side wiring.
