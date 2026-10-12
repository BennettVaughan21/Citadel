# ADR 0002 — Unprivileged LXC per project, Tailscale as the perimeter

- Status: accepted (2026-07)
- Deciders: Bennett Vaughan

## Context
Several unrelated projects (trading research, a news job, the orchestration brain) need to share one machine without sharing fate or secrets. Some of them handle credentials and call third-party services, so a bug or compromise in one must not reach the others. The machine also has to be reachable remotely for administration without being exposed to the internet.

Constraints: one Proxmox host, modest RAM, a single operator, and a build that can be torn down and recreated cheaply.

## Alternatives considered
| Option | Why not |
|---|---|
| Everything on one OS | No isolation: one compromised service sees every other project's files and secrets. |
| One VM per project | Stronger isolation, but each VM carries a full kernel and fixed RAM. On a single small host that cost buys little over unprivileged LXC for these workloads. |
| Privileged LXC | Container root maps to host root, so a container escape is a host compromise. Unprivileged containers map root to an unmapped UID range. |
| Port-forward SSH/web UI with a bastion host | Puts a login service on the public internet and adds a host to patch and watch. |

## Decision
- One **unprivileged LXC container per project**, independently created, snapshotted, rebuilt, or deleted.
- **Tailscale is the only remote entry point.** No port forwarding and no public bastion. The Proxmox firewall is default-deny inbound, allowing the management ports (SSH, web UI, console) from the Tailscale range and the LAN only.
- A uniform hardening baseline is applied to every container by one idempotent script (`playbooks/hardening-baseline.sh`): key-only SSH with root login disabled, a non-root sudo user, `ufw` default-deny, `fail2ban` (3 failures in 10 minutes bans for an hour), and unattended security updates.
- Tailscale node-key expiry is disabled, because silent expiry would cut off remote access. Re-authentication is done from a LAN session, never over a Tailscale-routed SSH session, which would drop mid-auth.

## Verification
An external scan of the SSH, web UI, and proxy ports returned closed, and the router has no port-forwarding rules.

## Consequences
- Small attack surface and cheap to rebuild.
- LXC has sharp edges that each cost time once and are documented in `docs/incidents.md`: TUN passthrough for Tailscale needs host-side config, `nesting=1` is needed for `systemctl restart` to behave in an unprivileged container, and Proxmox writes `/etc/resolv.conf` directly, so DNS must be set at container creation.
- All remote access depends on Tailscale being up. LAN access is the fallback, which is why re-auth is done locally.
- Tailscale is a third-party control plane. The trust placed in it is accepted for a homelab and would need revisiting for anything holding regulated data.
