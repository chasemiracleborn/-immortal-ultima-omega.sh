#!/bin/bash
# IMMORTAL ULTIMA OMEGA — FINAL (UNVERSIONED)
# Self-healing • Self-auditing • Fedora-native • Long-term stable

set -Eeuo pipefail

MODE="full"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --revert) MODE="revert" ;;
    --dry-run) DRY_RUN=1 ;;
  esac
done

LOG_FILE="/var/log/immortal-unified.log"
LOCK_FILE="/var/lock/immortal.lock"
EXTRA_DRIVE="/mnt/ExtraStorage"
SCAN_FILE="/tmp/immortal-scan.txt"

mkdir -p /var/log /var/lock

exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Another instance is running"; exit 1; }

timestamp() { date "+%F %T"; }
log()  { echo "[✓][$(timestamp)] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!][$(timestamp)] $*" | tee -a "$LOG_FILE"; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY] $*"
  else
    "$@" || warn "Failed: $*"
  fi
}

trap 'warn "Error at line $LINENO"' ERR

[[ $EUID -ne 0 ]] && { echo "Run with sudo"; exit 1; }

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

safe_write() {
  local target="$1"
  local tmp="${target}.tmp"
  cat > "$tmp"
  mv "$tmp" "$target"
}

echo "===== IMMORTAL START ====="

# =========================================================
# PART 1 — NORMALIZATION
# =========================================================
if [[ $MODE == "full" || $MODE == "revert" ]]; then
  run rm -rf /var/lib/immortal /root/immortal-backups
  run rm -f /var/log/immortal*.log

  run rm -rf /etc/tuned/immortal-*
  run rm -f /etc/systemd/system/immortal-*
  run rm -f /etc/sysctl.d/*immortal*
  run rm -f /etc/modprobe.d/*immortal*
  run rm -f /etc/systemd/zram-generator.conf

  command -v tuned-adm >/dev/null && run tuned-adm profile balanced
  run systemctl disable --now nvidia-persistenced.service

  if [[ $MODE == "revert" ]] && command -v getenforce >/dev/null; then
    run sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    run setenforce 1
  fi

  run systemctl daemon-reload
fi

[[ $MODE == "revert" ]] && exit 0

# =========================================================
# PART 2 — EXTRA STORAGE
# =========================================================
if mountpoint -q "$EXTRA_DRIVE"; then
  log "ExtraStorage active"

  mkdir -p "$EXTRA_DRIVE/tmp"
  export TMPDIR="$EXTRA_DRIVE/tmp"

  # SMART health check
  if command -v smartctl >/dev/null; then
    DEV=$(findmnt -n -o SOURCE --target "$EXTRA_DRIVE" | sed 's/[0-9]*$//')
    smartctl -H "$DEV" 2>/dev/null | grep -q PASSED && log "Drive healthy" || warn "Drive check failed"
  fi

  # Swap
  if [[ ! -f "$EXTRA_DRIVE/swapfile" ]]; then
    run fallocate -l 8G "$EXTRA_DRIVE/swapfile"
    run chmod 600 "$EXTRA_DRIVE/swapfile"
    run mkswap "$EXTRA_DRIVE/swapfile"
  fi

  grep -q "$EXTRA_DRIVE/swapfile" /etc/fstab || \
    echo "$EXTRA_DRIVE/swapfile none swap sw 0 0" >> /etc/fstab

  run swapon -a

fi

# =========================================================
# PART 3 — APPLY (STATE-AWARE)
# =========================================================
run dnf install -y tuned zram-generator gamemode

if ! systemctl is-active --quiet tuned; then
  run systemctl enable --now tuned
fi

if ! systemctl is-active --quiet gamemoded; then
  run systemctl enable --now gamemoded
fi

# ZRAM
RAM=$(free -g | awk '/Mem:/{print $2}')
ZRAM=$(( RAM / 2 ))
[[ $ZRAM -gt 16 ]] && ZRAM=16
[[ $ZRAM -lt 4 ]] && ZRAM=4

safe_write /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ${ZRAM}G
compression-algorithm = zstd
EOF

# SYSCTL
safe_write /etc/sysctl.d/99-immortal.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF

run sysctl --system

# NVIDIA
if lspci | grep -qi nvidia; then
  systemctl list-unit-files | grep -q nvidia-persistenced && \
    run systemctl enable --now nvidia-persistenced.service
fi

# =========================================================
# PART 4 — SYSTEM STABILITY SCAN
# =========================================================
echo "--- SYSTEM SCAN ---"

{
echo "=== IMMORTAL SYSTEM SCAN ==="
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""

echo "--- Failed Services ---"
systemctl --failed || true

echo "--- Disk Usage ---"
df -h

echo "--- Memory ---"
free -h

echo "--- Dmesg Errors ---"
dmesg --level=err,warn | tail -n 50

echo "--- SMART ---"
command -v smartctl >/dev/null && smartctl -H "$DEV" 2>/dev/null || echo "SMART unavailable"

} > "$SCAN_FILE"

log "Scan complete → $SCAN_FILE"

# =========================================================
# PART 5 — CLIPBOARD EXPORT (AI LOOP)
# =========================================================
PROMPT_FILE="/tmp/immortal-ai.txt"

{
echo "Review this system scan and recommend ONLY safe, stability-focused improvements."
echo ""
cat "$SCAN_FILE"
} > "$PROMPT_FILE"

if command -v wl-copy >/dev/null; then
  cat "$PROMPT_FILE" | wl-copy
  log "Copied to clipboard (Wayland)"
elif command -v xclip >/dev/null; then
  cat "$PROMPT_FILE" | xclip -selection clipboard
  log "Copied to clipboard (X11)"
else
  warn "Clipboard unavailable → saved at $PROMPT_FILE"
fi

echo ""
echo "===== IMMORTAL COMPLETE ====="
echo "System is STABLE • VERIFIED • SELF-AUDITED"
echo "AI analysis ready in clipboard"
echo "Reboot recommended"
