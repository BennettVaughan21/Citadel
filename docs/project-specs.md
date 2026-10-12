# Host and storage specs

## Storage layout
| Tier | Device | Use |
|---|---|---|
| `local-lvm` | internal drive (`pve/data` thin pool) | every container root filesystem; the brain must never depend on the USB disk to boot |
| `ssd-storage` | USB SSD (SanDisk Extreme, ~885 GB thin pool) | **backups only** (`ssd-storage/backups`, 300 G ext4 at `/mnt/ssd-backups`) |

## Rules that came from incidents (see `docs/incidents.md`)
- The USB disk runs on `usb-storage` (UAS disabled for `0781:55ae` via a modprobe quirk) and is activated at boot by `lvm-ssd-activate.service` to avoid a "no such logical volume" race.
- Watch **Meta% as well as Data%** on thin pools. The SSD pool's metadata was 8x undersized and was grown to 1 GiB.
- Never `dd` to the SSD. Snapshot SSD volumes sparingly: snapshots filling a thin pool corrupted it once.
- Backup directory mode is `750` (owner `root:100000`), not `700`, so unprivileged-container `vzdump` can traverse it.

## Backups
Nightly `vzdump` (snapshot mode, zstd) of CT110/111/113 at 02:30 America/New_York, keep 7 daily + 4 weekly, restore-tested. Design and runbook: `docs/backup-plan.md`. Monitoring: `monitoring/citadel-monitor.sh` alerts when any container's newest backup is older than 26 h or the SSD thin pool crosses 70% / 80% (Data% or Meta%).
