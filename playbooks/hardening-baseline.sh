#!/usr/bin/env bash
set -euo pipefail

# Citadel hardening baseline -- applies the standard config from CLAUDE.md
# (non-root sudo user, key-only SSH, ufw, fail2ban, unattended-upgrades,
# Tailscale, DNS) to any freshly-provisioned Ubuntu 24.04 LXC.
#
# Run INSIDE the container as root, e.g. from the Proxmox host:
#   pct exec <ctid> -- bash -s -- "$(cat ~/.ssh/id_ed25519.pub)" < hardening-baseline.sh
#
# No key is hardcoded here on purpose -- it's passed in at call time so this
# script stays generic and nothing secret/identifying lives in git.
#
# Safe to re-run: every step checks current state before changing anything.
# Host-side prerequisite: run host-tun-passthrough.sh <ctid> first if this
# container needs Tailscale -- tailscaled won't start without it.

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (pct exec runs as root by default)." >&2
  exit 1
fi

if [[ $# -ne 1 || -z "${1// /}" ]]; then
  echo "Usage: $0 \"<ssh-public-key-string>\"" >&2
  exit 1
fi

SSH_PUBKEY="$1"
TARGET_USER="admin"
SSHD_CONFIG="/etc/ssh/sshd_config"

export DEBIAN_FRONTEND=noninteractive

echo "== OS check =="
if ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
  echo "This script targets Ubuntu 24.04 LTS; /etc/os-release doesn't match. Aborting." >&2
  exit 1
fi

echo "== Package index =="
apt-get update -y >/dev/null

echo "== User: ${TARGET_USER} =="
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$TARGET_USER"
fi
usermod -aG sudo "$TARGET_USER"

echo "== SSH key (installed before any SSH hardening, to avoid lockout) =="
USER_HOME=$(eval echo "~${TARGET_USER}")
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$SSH_DIR"
touch "$AUTH_KEYS"
if ! grep -qF "$SSH_PUBKEY" "$AUTH_KEYS"; then
  echo "$SSH_PUBKEY" >> "$AUTH_KEYS"
fi
chmod 600 "$AUTH_KEYS"
chown "$TARGET_USER:$TARGET_USER" "$AUTH_KEYS"

echo "== SSH hardening (idempotent -- replaces existing directives, doesn't append duplicates) =="
set_sshd_directive() {
  local key="$1" value="$2"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}
set_sshd_directive "PermitRootLogin" "no"
set_sshd_directive "PasswordAuthentication" "no"
set_sshd_directive "PubkeyAuthentication" "yes"

echo "== Validating sshd config before restart =="
if ! sshd -t; then
  echo "sshd -t failed validation -- NOT restarting sshd. Fix ${SSHD_CONFIG} and rerun." >&2
  exit 1
fi
systemctl restart ssh

echo "== ufw =="
apt-get install -y ufw >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp >/dev/null
ufw --force enable >/dev/null

echo "== fail2ban =="
apt-get install -y fail2ban >/dev/null
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
ignoreip = 127.0.0.1/8 ::1 192.0.2.0/24 100.64.0.0/10

[sshd]
enabled = true
EOF
systemctl enable fail2ban >/dev/null
systemctl restart fail2ban

echo "== unattended-upgrades =="
apt-get install -y unattended-upgrades >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable unattended-upgrades >/dev/null
systemctl restart unattended-upgrades

echo "== DNS =="
RESOLVED_CONF="/etc/systemd/resolved.conf"
if grep -qE "^[#[:space:]]*DNS=" "$RESOLVED_CONF"; then
  sed -i -E "s|^[#[:space:]]*DNS=.*|DNS=1.1.1.1|" "$RESOLVED_CONF"
else
  echo "DNS=1.1.1.1" >> "$RESOLVED_CONF"
fi
systemctl restart systemd-resolved

echo "== Tailscale =="
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if tailscale status >/dev/null 2>&1; then
  echo "Tailscale already up, skipping 'tailscale up'."
else
  echo "Run this now and complete auth at the printed URL (interactive, on purpose -- no auth key stored anywhere):"
  tailscale up
fi

cat <<'EOF'

==================================================================
Hardening baseline applied.
REMINDER: disable key expiry for this node in the Tailscale admin
console (https://login.tailscale.com/admin/machines). Do this from
a local/LAN session, never over Tailscale-routed SSH, to avoid
dropping mid-auth.
==================================================================
EOF
