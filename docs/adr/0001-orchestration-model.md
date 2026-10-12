# ADR 0001 — Claude orchestration brain with least-privilege reach

- Status: accepted (2026-10)
- Deciders: Bennett Vaughan

## Context
The fleet is managed from a dedicated container (the *brain*) where Claude Code turns plain-English instructions into changes. An agent that can change infrastructure is also an attack surface: whatever credentials the brain holds are the blast radius of a bad prompt, a bug, or a compromise of the brain itself.

## Decision
1. **Hub-and-spoke SSH, one direction only.** Brain → leaf. No leaf holds a key to reach the brain or another leaf. (An earlier full mesh let a compromised trader pivot into the brain; collapsed 2026-10-08.)
2. **Host access is read-only sudo.** The brain's Proxmox account may run `pct list/config/status/snapshot/listsnapshot`, `pvesm`, and `lvs` — nothing that mutates. Any mutating `pct` access is effectively host root, so it is withheld.
3. **Writes go through a scoped API token and Terraform**, with a reviewed `plan` before any `apply`. The token starts audit-only and is ACL-scoped per container.
   *Status of this item (2026-10): designed and the Terraform is written and passes `validate` in CI, but it has not been applied. The token does not exist yet, so today the brain's host access is the read-only sudo in item 2 and nothing more.*
4. **Humans approve consequential actions.** Security changes, destructive commands, deletions, publishing, and anything on production workloads need explicit approval; the plan is stated in plain English first.
5. **Git is the ground truth.** Every change is committed, and the operating brief (`CLAUDE.md`) is updated with each one.
6. **Metered usage is capped by design** (e.g. 2 calls/day, 40/month on the news job).

## Consequences
- Safer: a compromised or misled brain cannot rewrite the host or reach production workloads it has no ACL on.
- Slower: some tasks (restore drills, disk removal) need a human or a later privilege grant. Accepted — the friction is the control.
- Raw `lxc.*` config is not Terraform-manageable and stays in host-side scripts.
