# ADR 0004 — USB SSD holds backups, never running containers

- Status: accepted (2026-10-08)
- Deciders: Bennett Vaughan

## Context
Citadel had snapshots but no backups: every snapshot sat in the same thin pool as its container, so one disk failure would have taken both.

The only second physical disk is a USB-attached SSD, and it had already caused two problems:
- **I/O errors** from a loose connection plus instability under the UAS transport. Fixed by reseating the cable and disabling UAS for that device (see `docs/incidents.md`).
- **A thin-pool corruption**, probably linked to a metadata volume that was far too small: 112 MiB, against roughly 450 MiB needed for a full pool, and already 10% used when the pool held 0.1% data. Metadata exhaustion corrupts a thin pool regardless of free data space. Grown to 1 GiB.

## Alternatives considered
| Option | Why not |
|---|---|
| Snapshots only | Same disk, same failure. Not a backup. |
| Run containers on the SSD and back up internally | Puts an unreliable USB link under live workloads. A dropout would crash containers. |
| Off-site or cloud copy first | A good end state, but not needed to close the immediate gap of having no backup at all. Still open as a follow-up. |

## Decision
Containers stay on the internal disk. The USB SSD holds `vzdump` backups only.
- Nightly at 02:30 local time, snapshot mode, zstd compression, all containers.
- A 300 GB thin volume (ext4) on the SSD, mounted with `nofail` so boot still completes if the disk is unplugged.
- Retention: 7 daily and 4 weekly. A full set is about 3 GB, so retention fits well within the volume.
- The backup directory is root-owned and not world-readable, because the archives contain every container's secrets. Mode 700 broke unprivileged-container backups, because `vzdump` runs `tar` as an unmapped host UID that must traverse the directory, so the working mode is 750, with group access for that unmapped UID range.

## Verification
A restore of the news-briefing container to a scratch container ID passed (files and hostname verified, then the scratch container destroyed).

## Monitoring
Proxmox's own failure notifications push to a phone. A job that never runs sends no failure notice, so an hourly monitor on the brain separately alerts when any container's newest backup is older than 26 hours, and when the SSD pool crosses 70% (warning) or 80% (critical) on either data or metadata usage.

## Consequences
- A USB dropout fails one night's backup. It cannot crash a container.
- Restoring after an internal-disk failure comes from the SSD.
- **Not yet done:** an off-site copy, and the monthly automated restore drill (written, not installed, because it needs host privilege). Today the restore evidence is one manual test.
