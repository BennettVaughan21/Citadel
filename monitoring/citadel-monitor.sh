#!/usr/bin/env bash
# Citadel health monitor. Runs on the brain; reads the Proxmox host over the
# read-only `proxmox-host` SSH alias (sudo: pvesm list, lvs only).
#   - newest vzdump archive per CT must be younger than MAX_BACKUP_AGE_H (default 26)
#   - ssd-storage/data Data% and Meta% warn at WARN_PCT (70), alert at CRIT_PCT (80)
# Alerts go to ntfy via $NTFY_URL (set in an untracked env file; never commit it).
# With --test, thresholds are forced low so the alert path can be exercised.
set -uo pipefail

ENV_FILE="${CITADEL_MONITOR_ENV:-$HOME/.config/citadel-monitor.env}"
# shellcheck source=/dev/null
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

CTS="${CTS:-110 111 113}"
MAX_BACKUP_AGE_H="${MAX_BACKUP_AGE_H:-26}"
WARN_PCT="${WARN_PCT:-70}"
CRIT_PCT="${CRIT_PCT:-80}"
[ "${1:-}" = "--test" ] && { MAX_BACKUP_AGE_H=0; WARN_PCT=0; CRIT_PCT=1; }

problems=()
now=$(date +%s)

list=$(ssh -o BatchMode=yes -o ConnectTimeout=10 proxmox-host 'sudo pvesm list ssd-backups' 2>&1) \
  || problems+=("cannot list ssd-backups: ${list:0:120}")

for ct in $CTS; do
  newest=$(grep -oE "vzdump-lxc-${ct}-[0-9_]+-[0-9_]+" <<<"$list" | sort | tail -1)
  if [ -z "$newest" ]; then problems+=("CT$ct: no backups found"); continue; fi
  ts=${newest#vzdump-lxc-${ct}-}; d=${ts%%-*}; t=${ts#*-}
  epoch=$(date -d "${d//_/-} ${t//_/:}" +%s 2>/dev/null) || { problems+=("CT$ct: unparsable $newest"); continue; }
  age_h=$(( (now - epoch) / 3600 ))
  [ "$age_h" -ge "$MAX_BACKUP_AGE_H" ] && problems+=("CT$ct newest backup is ${age_h}h old (limit ${MAX_BACKUP_AGE_H}h)")
done

lv=$(ssh -o BatchMode=yes -o ConnectTimeout=10 proxmox-host \
  'sudo lvs --noheadings --separator , -o data_percent,metadata_percent ssd-storage/data' 2>&1) \
  || problems+=("cannot read thin pool: ${lv:0:120}")
if [ -n "${lv:-}" ] && [[ "$lv" =~ ^[[:space:]]*([0-9.]+),([0-9.]+) ]]; then
  for pair in "Data:${BASH_REMATCH[1]}" "Meta:${BASH_REMATCH[2]}"; do
    name=${pair%%:*}; pct=${pair#*:}; whole=${pct%.*}
    if   [ "$whole" -ge "$CRIT_PCT" ]; then problems+=("CRITICAL: ssd thin pool $name% = $pct")
    elif [ "$whole" -ge "$WARN_PCT" ]; then problems+=("WARNING: ssd thin pool $name% = $pct"); fi
  done
else
  problems+=("could not parse thin pool usage")
fi

if [ ${#problems[@]} -eq 0 ]; then
  echo "OK: backups fresh, thin pool within limits"
  # Dead-man heartbeat: external ping so a silently dead monitor is noticed.
  [ -n "${HEARTBEAT_URL:-}" ] && curl -fsS -m 10 "$HEARTBEAT_URL" >/dev/null || true
  exit 0
fi

msg=$(printf '%s\n' "${problems[@]}")
echo "$msg" >&2
if [ -n "${NTFY_URL:-}" ]; then
  curl -fsS -m 10 -H "Title: citadel monitor" -H "Priority: high" -d "$msg" "$NTFY_URL" >/dev/null \
    || echo "ntfy delivery failed" >&2
else
  echo "NTFY_URL not set; alert logged only" >&2
fi
exit 1
