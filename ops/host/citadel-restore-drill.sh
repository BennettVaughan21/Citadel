#!/usr/bin/env bash
# Monthly restore drill. Runs ON THE PROXMOX HOST as root (systemd timer), so the
# brain needs no extra privilege.
#
# Restores the newest CT113 backup into a scratch CT, MOUNTS its filesystem to
# verify contents, then destroys the scratch CT. It never STARTS the restored
# container: a booted copy would bring up tailscaled with CT113's node identity
# and fight the live container, and it would reuse CT113's IP.
#
# Result is pushed to ntfy via $NTFY_URL (from /etc/citadel/restore-drill.env, 0600).
set -uo pipefail

SRC_CT="${SRC_CT:-113}"
SCRATCH="${SCRATCH:-9113}"
STORAGE_SRC="${STORAGE_SRC:-ssd-backups}"
STORAGE_DST="${STORAGE_DST:-local-lvm}"
CHECK_PATH="${CHECK_PATH:-/home/admin/DAILY-NEWS-BRIEFING/generate_report.py}"
ENV_FILE="${ENV_FILE:-/etc/citadel/restore-drill.env}"
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

notify() {  # $1 = message, $2 = priority
  echo "$1"
  [ -n "${NTFY_URL:-}" ] && curl -fsS -m 10 -H "Title: citadel restore drill" -H "Priority: ${2:-default}" -d "$1" "$NTFY_URL" >/dev/null || true
}
fail() { cleanup; notify "FAILED: $1" high; exit 1; }
cleanup() {
  pct unmount "$SCRATCH" >/dev/null 2>&1 || true
  if pct config "$SCRATCH" 2>/dev/null | grep -q '^description:.*citadel-restore-drill'; then
    pct destroy "$SCRATCH" --purge >/dev/null 2>&1 || echo "WARN: could not destroy scratch CT $SCRATCH" >&2
  fi
}

# Refuse to run over anything that is not a leftover of this script.
if pct status "$SCRATCH" >/dev/null 2>&1; then
  pct config "$SCRATCH" | grep -q '^description:.*citadel-restore-drill' \
    || { notify "ABORT: CTID $SCRATCH exists and is not a drill scratch CT" high; exit 1; }
  cleanup
fi

latest=$(pvesm list "$STORAGE_SRC" --vmid "$SRC_CT" | awk 'NR>1{print $1}' | sort | tail -1)
[ -n "$latest" ] || fail "no backup found for CT$SRC_CT"

start=$(date +%s)
pct restore "$SCRATCH" "$latest" --storage "$STORAGE_DST" --unprivileged 1 >/dev/null 2>&1 \
  || fail "pct restore of $latest failed"
pct set "$SCRATCH" --description "citadel-restore-drill scratch (safe to delete)" --delete net0 >/dev/null 2>&1 \
  || fail "could not tag/strip network on scratch CT"

mnt=$(pct mount "$SCRATCH" 2>&1 | sed -n "s/.*mounted CT $SCRATCH in '\(.*\)'.*/\1/p")
[ -n "$mnt" ] && [ -d "$mnt" ] || fail "could not mount restored CT filesystem"
[ -f "$mnt$CHECK_PATH" ] || fail "restored filesystem missing $CHECK_PATH"

cleanup
secs=$(( $(date +%s) - start ))
notify "OK: restored ${latest##*/} to scratch CT $SCRATCH, verified $CHECK_PATH, destroyed scratch (${secs}s)"
