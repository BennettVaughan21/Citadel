# Backup plan: nightly vzdump to the USB SSD

**Status:** LIVE (2026-10-08). Steps 1–8 done. Step 0 (orphan disk) still optional/pending; reboot test pending.
**Owner of execution:** the human, as root on the Proxmox host (`proxmox`, `192.0.2.23`). Brain only has read-only sudo there.
**Part of:** Phase 1 (Infrastructure-as-Code). Once proven by hand, the job definition moves into Ansible.

---

## Why

Citadel has **snapshots but no backups.** Every snapshot (`brain-hardened-baseline`, `news-briefing-hardened-baseline`, `trading-baseline-2026-10-08`) lives in the same `pve/data` thin pool on the internal disk as the container it protects. If the internal disk dies, every container *and* every snapshot goes with it.

The USB SSD (`ssd-storage`, ~885 GB, essentially empty) is the obvious second physical disk. Backups are the right workload for it because of how they fail:

| If the USB SSD drops out while... | Result |
|---|---|
| ...running a container on it | container crashes, filesystem may corrupt |
| ...writing a backup to it | that night's backup fails; all containers keep running |

So: **containers stay on `local-lvm`; the SSD holds backups.** (`local-lvm` is 8% used, so there's no capacity reason to move anything to the SSD.)

## Finding: the SSD thin pool's metadata is ~8× undersized — fix first

Read-only inspection on 2026-10-08:

| Pool | Data size | Chunk | Metadata (`tmeta`) | Meta% now |
|---|---|---|---|---|
| `pve/data` (internal) | 348.82 GiB | 512 KiB | 3.56 GiB | 0.78% |
| `ssd-storage/data` (USB) | 884.69 GiB | 64 KiB | **0.11 GiB (112 MiB)** | **10.46% at only 0.12% data used** |

`thin_metadata_size -b 64k -s 885g -m 20` says a full pool needs **~450 MiB** of metadata, and even a single 300 GiB backup volume needs **~152 MiB** — more than the pool has. When thin-pool *metadata* runs out, the pool goes read-only or corrupts, regardless of how much *data* space is free.

This is very plausibly what caused the earlier "thin pool hit 100% and corrupted" incident noted in CLAUDE.md (root cause not confirmed). Either way, **writing backups into this pool before fixing the metadata would recreate that failure.**

The VG has **46.57 GiB unallocated**, so the metadata can be grown in place, non-destructively.

## Design

| Decision | Choice | Why |
|---|---|---|
| Where backups live | New thin LV `ssd-storage/backups`, 300 GiB, ext4, mounted at `/mnt/ssd-backups` | `vzdump` needs a directory store, not raw thin pool. 46 GiB of free VG space is too small for a thick LV. |
| Overprovisioning | **None.** Sum of thin LV sizes stays ≤ pool size (300 + 20 orphan ≪ 885) | Pool data can then never hit 100%, no matter what. |
| Metadata | Grow `tmeta` 0.11 → 1 GiB before anything else | ~2× headroom over the full-pool estimate. |
| Mount safety | `nofail` + Proxmox `is_mountpoint yes` | Boot doesn't hang if the SSD is missing, and Proxmox refuses to write backups into the root filesystem if the mount isn't there. |
| What's backed up | CT110 (brain), CT111 (trading-workload), CT113 (news-briefing) | Whole fleet. ~16 GiB of real data total; zstd roughly halves it. |
| Mode | `snapshot` | No downtime; works for LXC on lvmthin. |
| Schedule | Daily 02:30 | Quiet hours; finishes well before news-briefing's 06:00 run. |
| Retention | `keep-daily=7, keep-weekly=4` | ~11 restore points per container; worst case ~110 GiB, well under 300. |

**Explicitly not solved here:** off-site copies. The internal disk and the SSD are in the same box in the same house. Encrypted off-site sync (e.g. restic → cloud bucket) is a later step.

---

## Runbook

Run as **root on the Proxmox host**. After each step, paste the output back to brain to check it before moving on.

### Step 0 — (optional, independent) remove the orphaned old brain disk

`ssd-storage:vm-110-disk-0` is listed as `unused0` on CT110 — most likely the brain's rootfs from before it moved to `local-lvm`. Deleting it is **irreversible**. If you want to look first:

```bash
pct config 110 | grep unused        # expect: unused0: ssd-storage:vm-110-disk-0
mkdir -p /tmp/oldbrain && mount -o ro /dev/ssd-storage/vm-110-disk-0 /tmp/oldbrain && ls /tmp/oldbrain/home; umount /tmp/oldbrain
```

Then, only if nothing in there matters:

```bash
pct set 110 --delete unused0        # removes the config entry AND destroys the volume
```

Skipping this step doesn't block anything below.

### Step 1 — grow the thin-pool metadata

```bash
lvs -a -o lv_name,lv_size,data_percent,metadata_percent ssd-storage    # before
lvextend --poolmetadatasize 1G ssd-storage/data
lvs -a -o lv_name,lv_size,data_percent,metadata_percent ssd-storage    # after
vgs ssd-storage
```

**Expect:** `[data_tmeta]` ≈ 1.00g, `Meta%` drops to ~1%, `[lvol0_pmspare]` also grows, VG free drops by ~2 GiB. Works online.

### Step 2 — create and format the backup volume

```bash
lvcreate -V 300G -T ssd-storage/data -n backups
mkfs.ext4 -L citadel-backups /dev/ssd-storage/backups
mkdir -p /mnt/ssd-backups
```

### Step 3 — mount it at boot, safely

```bash
cp /etc/fstab /etc/fstab.bak-$(date +%F)
echo '/dev/ssd-storage/backups /mnt/ssd-backups ext4 defaults,noatime,nofail,x-systemd.requires=lvm-ssd-activate.service,x-systemd.device-timeout=30s 0 2' >> /etc/fstab
systemctl daemon-reload
mount /mnt/ssd-backups
findmnt /mnt/ssd-backups && df -h /mnt/ssd-backups
```

`x-systemd.requires=lvm-ssd-activate.service` orders the mount after the existing service that activates the SSD's VG at boot.

### Step 4 — register it with Proxmox

```bash
pvesm add dir ssd-backups --path /mnt/ssd-backups --content backup \
  --is_mountpoint yes --prune-backups keep-daily=7,keep-weekly=4
pvesm status
```

### Step 5 — first backup, by hand

```bash
vzdump 110 111 113 --storage ssd-backups --mode snapshot --compress zstd
ls -lh /mnt/ssd-backups/dump/
lvs -o lv_name,data_percent,metadata_percent ssd-storage
```

**Expect:** three `vzdump-lxc-<id>-*.tar.zst` files plus logs; no errors; `Meta%` still low.

### Step 5b — lock down backup file permissions

Found after Step 5: `/mnt/ssd-backups/dump` was `755` and the archives `644`, so **any** host user (including brain's `claude-provisioner`) could read full copies of every container: SSH private keys, GitHub deploy keys, Claude auth.

```bash
chown root:100000 /mnt/ssd-backups /mnt/ssd-backups/dump
chmod 750 /mnt/ssd-backups /mnt/ssd-backups/dump
```

**Do NOT use `chmod 700`.** That was the first attempt (2026-10-08) and it broke every backup with `tar: ...tmp: Cannot open: Permission denied`. For unprivileged containers, vzdump runs `tar` inside the container's user namespace (`lxc-usernsexec -m u:0:100000`), i.e. as host uid/gid 100000, and that process must traverse into `dump/`. Group `100000` + `750` lets the container-root mapping in while still locking out other host users. Caught by a "Run now" test of the scheduled job. Without that test it would have failed silently at 02:30. If a future container uses a non-default idmap, revisit this.

Brain then checks backups via `sudo pvesm list ssd-backups` (Step 8) instead of reading the directory directly.

### Step 6 — restore test (the step that makes it a real backup)

Restore CT113's backup to a throwaway ID **without starting it**. A started copy would fight the real CT113 for `192.0.2.33`.

```bash
pct restore 9113 /mnt/ssd-backups/dump/vzdump-lxc-113-<timestamp>.tar.zst --storage local-lvm --unique 1
pct mount 9113
ls /var/lib/lxc/9113/rootfs/home/admin/DAILY-NEWS-BRIEFING | head
cat /var/lib/lxc/9113/rootfs/etc/hostname
pct unmount 9113
pct destroy 9113
```

**Expect:** the repo directory is present, and the hostname reads `news-briefing`. Then the throwaway is gone.

### Step 7 — schedule it nightly

```bash
pvesh create /cluster/backup --id citadel-nightly --schedule '02:30' \
  --storage ssd-backups --vmid 110,111,113 --mode snapshot --compress zstd \
  --enabled 1 --notes-template '{{guestname}}'
pvesh get /cluster/backup --output-format yaml
```

### Step 8 — let brain watch it (read-only)

Add one line to `/etc/sudoers.d/claude-provisioner` so brain can list backups (check with `visudo -c`):

```
claude-provisioner ALL=(root) NOPASSWD: /usr/sbin/pvesm list ssd-backups
```

Brain can then check the age of the newest backup per container (it can no longer read the directory itself after Step 5b), and Meta%/Data% via `lvs`. Proper alerting comes in Phase 2.

---

## Rollback

Each step can be undone in reverse order:

```bash
pvesh delete /cluster/backup/citadel-nightly
pvesm remove ssd-backups
umount /mnt/ssd-backups && cp /etc/fstab.bak-<date> /etc/fstab && systemctl daemon-reload
lvremove ssd-storage/backups
```

The metadata extension (Step 1) can't be shrunk back. It doesn't need to be; it's strictly safer.

## Things to verify along the way

- **TRIM:** the SSD reports no discard support under `usb-storage`/BOT (`lsblk -D` shows `DISC-MAX 0B`). Pruned backups may therefore not hand space back to the thin pool. That's acceptable because the backup LV is capped at 300 GiB and the pool isn't overprovisioned. After the first prune, run `fstrim -v /mnt/ssd-backups` and check whether `Data%` drops. That tells us whether dm-thin reclaims the space anyway. *Early signal (2026-10-08): `mkfs.ext4` reported "Discarding device blocks: done" against the thin LV, and the pool showed only 0.29% data afterwards, so dm-thin does accept discards at the thin layer.*
- **Failure notifications:** `mail-to-root` goes nowhere (no relay). Fixed 2026-10-08 with a Proxmox webhook target `ntfy` → ntfy.sh push to phone (Datacenter → Notifications; body `{{ message }}`, headers `Title: {{ title }}`, `Priority: high`) plus a matcher for severity error/warning. Test notifications verified end-to-end. Phase 2 alerting still has to cover "newest backup too old" (a job that never runs sends nothing).
- **Monitoring thresholds** (feeds Phase 2): alert on `Meta%` > 50% or `Data%` > 80% for `ssd-storage/data`, and when the newest backup of any container is more than 26h old.

## Success criteria

- [x] `ssd-storage/data` metadata ≥ 1 GiB (done 2026-10-08: tmeta + pmspare 112 MiB → 1 GiB, Meta% 10.46 → 1.62, VG free 46.57 → 44.79 GiB)
- [x] `/mnt/ssd-backups` mounted (2026-10-08: thin LV `ssd-storage/backups` 300G, ext4 label `citadel-backups`, UUID 1fcc84b8-2965-4031-beeb-f11450007bb8, fstab entry added, backup at `/etc/fstab.bak-2026-10-08`)
- [ ] `/mnt/ssd-backups` survives a host reboot, and boot still completes with the SSD unplugged
- [x] Manual backup of 110/111/113 succeeded (2026-10-08, ~2 min total: 110 → 704M, 111 → 1.7G, 113 → 753M zstd; ~3.1G per full set, so full retention ≈ 35G, far under 300G. Pool afterwards: Data 1.12%, Meta 1.66%)
- [x] CT113 restore test passed and the throwaway was destroyed (2026-10-08: restored to CT9113 on local-lvm at 430 MiB/s, never started, project files + hostname `news-briefing` verified via `pct mount`, then destroyed; `pct list` back to 110/111/113)
- [x] Backup dir permissions locked down (`root:100000 750`, Step 5b, 2026-10-08; brain gets Permission denied)
- [x] Scheduled job exercised via "Run now" (2026-10-08 17:38, all 3 OK; earlier same-day set pruned by keep-daily as expected)
- [x] `citadel-nightly` job exists (2026-10-08; schedule `02:30` in host TZ America/New_York = 06:30 UTC)
- [ ] First scheduled run (2026-10-09 02:30 ET) produced fresh backups
- [x] Brain can list backups via `sudo pvesm list ssd-backups` (Step 8, verified)
- [x] CLAUDE.md storage section + README updated, committed
