#!/usr/bin/env bash
set -euo pipefail

# Run on the Proxmox host, before creating/hardening any unprivileged LXC
# that needs Tailscale. Adds the TUN device passthrough lines to the
# container's config so tailscaled can actually start inside it -- without
# this, Tailscale silently fails to come up (bit us on CT110).
#
# Safe to re-run: only appends lines that aren't already present, and only
# restarts the container if something actually changed.
#
# Usage: host-tun-passthrough.sh <ctid>

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <ctid>" >&2
  exit 1
fi

CTID="$1"
CONF="/etc/pve/lxc/${CTID}.conf"

if [[ ! -f "$CONF" ]]; then
  echo "No such container config: $CONF" >&2
  exit 1
fi

TUN_LINES=(
  "lxc.cgroup2.devices.allow: c 10:200 rwm"
  "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
)

changed=0
for line in "${TUN_LINES[@]}"; do
  if ! grep -qF "$line" "$CONF"; then
    echo "$line" >> "$CONF"
    changed=1
  fi
done

if [[ "$changed" -eq 1 ]]; then
  echo "TUN passthrough added to $CONF -- restarting container $CTID..."
  pct restart "$CTID"
else
  echo "TUN passthrough already present in $CONF, nothing to do."
fi
