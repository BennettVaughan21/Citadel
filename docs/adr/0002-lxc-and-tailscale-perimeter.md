# ADR 0002 — Unprivileged LXC per project, Tailscale as the perimeter

- Status: accepted (2026-07)

## Context
Several unrelated projects (trading research, a news job, the orchestration brain) need to share one machine without sharing fate or secrets, and the machine must be reachable remotely without exposing it.

## Decision
- One **unprivileged LXC container per project**, independently created, snapshotted, rebuilt, or deleted. Lightweight enough for a single host; stronger isolation than processes on one OS, cheaper than VMs.
- **Tailscale is the only remote entry point.** No port forwarding, no public bastion.
- A uniform hardening baseline is applied to every container by one idempotent script (`playbooks/hardening-baseline.sh`).

## Consequences
- Small attack surface and cheap to rebuild, at the cost of LXC quirks (TUN passthrough for Tailscale needs host-side config; `nesting=1` is needed for `systemctl restart` to behave; DNS must be set at creation). Each is documented in the incident log.
- All remote access depends on Tailscale being up; LAN access is the fallback.
