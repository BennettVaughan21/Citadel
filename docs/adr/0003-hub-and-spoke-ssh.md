# ADR 0003 — Hub-and-spoke SSH (brain → leaf only)

- Status: accepted (2026-10-08), supersedes the 2026-08 full mesh

## Context
Every node could SSH to every other node. A compromised leaf (e.g. an internet-facing trading workload) could pivot into the brain and from there to the whole fleet.

## Decision
Access is one-directional: the brain holds one fleet key authorized on each leaf; no container can SSH into the brain or another leaf. Leaves hold no fleet keys (only per-repo GitHub deploy keys). Verified after the change: brain → leaves succeeds, leaf → brain is refused.

## Consequences
- A compromised leaf has no network-credential path to its peers or the brain.
- Anything a leaf needs from another node must be pulled by the brain. Accepted.
