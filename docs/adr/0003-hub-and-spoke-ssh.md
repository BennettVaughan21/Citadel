# ADR 0003 — Hub-and-spoke SSH (brain → leaf only)

- Status: accepted (2026-10-08), supersedes the 2026-08 full mesh
- Deciders: Bennett Vaughan

## Context
From 2026-08-01 to 2026-10-08 the fleet used a full SSH mesh: every node held a key authorized on every other node. It was convenient while building, but it meant a compromise of any container, including one that makes outbound calls to third-party services, gave an attacker a credential path to the brain and from there to the whole fleet.

An audit of the authorized keys also found stale entries: a key belonging to a container that had since been deleted, and a laptop key that was redundant with the operator's main admin key.

## Alternatives considered
| Option | Why not |
|---|---|
| Keep the full mesh | The lateral-movement risk is the problem being solved. |
| Bastion or jump host | Adds a host and another key store, and the brain already plays the management role. |
| Per-service credentials or an SSH CA | More machinery than a four-node fleet needs. Worth revisiting if the fleet grows. |

## Decision
Access is one-directional. The brain holds one fleet key, and its public half is the only fleet key authorized on each leaf (next to the operator's personal key). The brain's own `authorized_keys` contains only the operator's key, so **no container can SSH into the brain or into another leaf.** Leaves hold no fleet keys, only per-repo GitHub deploy keys scoped to their own project.

Removed in the change: the trading container's mesh keypair and its authorization on the brain, the deleted container's key, and the redundant laptop key (including its private half on the laptop). Backups of each `authorized_keys` were kept before editing.

## Verification
After the change: brain → each leaf and brain → host succeed, and leaf → brain is refused. The operator's laptop access was re-verified before the old laptop key was retired.

## Consequences
- A compromised leaf has no network-credential path to its peers or the brain.
- Anything a leaf needs from another node has to be pulled by the brain.
- **The brain is now the highest-value target:** its fleet key reaches every leaf. This is accepted because the brain is not internet-facing, its host access is read-only sudo (ADR 0001), and consequential actions need human approval. Protecting the brain is the main remaining security task.
