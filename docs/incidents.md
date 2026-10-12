# Incidents and lessons learned

Blameless notes on things that broke, how they were diagnosed, and what changed. Each led to a documented rule or a monitor.

## 1. USB SSD I/O errors (UAS)
- **Symptom:** UAS I/O errors (`err -75`) on the USB SSD; volumes unreliable.
- **Cause:** a loose USB connection, plus instability under the UAS transport.
- **Fix:** reseated into a rear USB 3 port; disabled UAS for the device (`usb-storage` quirk + initramfs rebuild); added a unit to activate the VG at boot.
- **Lesson:** a flaky transport is a reason to keep the disk off the critical path (ADR 0004).

## 2. Thin-pool metadata undersized
- **Found:** during backup planning, 2026-10-08. The SSD pool had 112 MiB of metadata against ~450 MiB needed for a full pool, already 10.46% used at 0.12% data.
- **Why it matters:** exhausting thin-pool *metadata* corrupts the pool regardless of free data space, and likely relates to an earlier corruption incident.
- **Fix:** grew metadata to 1 GiB in place (Meta% 10.46 → 1.62). The monitor now alerts on Meta% as well as Data%.
- **Lesson:** size and watch metadata, not only data.

## 3. Full-mesh SSH let a leaf pivot to the brain
- **Finding:** every node could reach every other; a compromised trader could reach the brain and everything else.
- **Fix:** collapsed to hub-and-spoke (ADR 0003) and removed stale keys, after verifying a retired key was redundant before deleting it.

## 4. Backups failed after tightening permissions
- **Symptom:** every backup failed after the backup directory was set to mode `700`.
- **Cause:** unprivileged-container `vzdump` runs `tar` as host uid 100000, which must traverse the directory.
- **Fix:** `root:100000` mode `750`; a "Run now" test and a CT113 restore test both passed.
- **Lesson:** least privilege has to be tested against the real consumer.

## 5. Brain could not reach the Proxmox host
- **Symptom:** SSH timeouts, followed by a long packet-level investigation.
- **Cause:** the SSH alias pointed at the home router (`.1`), not the host. The earlier firewall theory was a red herring.
- **Lesson:** check the target before debugging the path.

## 6. Timezone change triggered a catch-up run
- **Symptom:** a 06:00 timer was actually firing at 02:00 ET (container on UTC). Switching timezone caused `Persistent=true` to run an extra job.
- **Mitigation:** a hard usage cap held the extra run to a non-LLM fallback.
- **Lesson:** `Persistent=true` plus a timezone change equals a catch-up run; caps must be independent of schedules.

## 7. New containers: DNS and `systemctl` hangs
- **DNS:** Proxmox injects `/etc/resolv.conf` itself, so `resolved.conf` changes did nothing and a fresh container silently pointed at the unreachable Tailscale resolver. Set `--nameserver` at creation.
- **Hangs:** `systemctl restart` hung in an unprivileged container without `nesting=1`. Now a default.
