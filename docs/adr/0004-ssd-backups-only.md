# ADR 0004 — USB SSD holds backups, never running containers

- Status: accepted (2026-10-08)

## Context
Citadel had snapshots but no backups: every snapshot sat in the same thin pool as its container. The only second physical disk is a USB SSD that has had a loose-cable/UAS incident and a thin-pool corruption.

## Decision
Containers stay on the internal disk. The USB SSD holds nightly `vzdump` backups only.

## Consequences
- A USB dropout fails one night's backup; it cannot crash a container. Restoring after an internal-disk failure comes from the SSD.
- Failed jobs push-notify via ntfy, and a separate monitor alerts on stale backups, since a job that never runs sends no failure notification. An off-site copy remains open.
