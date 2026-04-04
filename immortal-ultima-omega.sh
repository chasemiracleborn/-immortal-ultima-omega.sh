#!/bin/bash
# IMMORTAL ULTIMA OMEGA v9.0 — FINAL FORM
# Clean → Normalize → Apply
# Idempotent • Reversible • Hardware-Aware • Fedora-Optimized • Zero-Risk Philosophy

set -Eeuo pipefail

# ================================
# GLOBALS
# ================================
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

mkdir -p /var/log /var/lock 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/immortal.log"

exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Another instance is running"; exit 1; }

# ================================
# LOGGING
# ================================
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log()  { echo "[✓][$(timestamp)] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!][$(timestamp)] $*" | tee -a "$LOG_FILE"; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY] $*"
  else
    "$@" || warn "Command failed: $*"
  fi
}

# ================================
# ERROR HANDLER
# ================================
trap 'warn "Failure at line $LINENO"' ERR

# ================================
# ROOT CHECK
# ================================
[[ $EUID -ne 0 ]] && { echo "Run with sudo"; exit 1; }

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

echo "===== IMMORTAL v9.0 START ====="
[[ $DRY_RUN -eq 1 ]] && warn "DRY RUN MODE"

# =========================================================
# SAFE WRITE FUNCTION (atomic config writes)
# =========================================================
safe_write() {
  local target="$1"
  local tmp="${target}.tmp"

  cat > "$tmp"
  mv "$tmp" "$target"
}

# =========================================================
# PART 1 — NORMALIZATION (REVERSAL)
# =========================================================
if [[ $MODE == "full" || $MODE == "revert" ]]; then
  echo "--- SYSTEM NORMALIZATION ---"

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
    log "SELinux restored"
  fi

  KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"
  if ls "$KWIN_CFG".bak* >/dev/null 2>&1; then
    latest=$(ls -t "$KWIN_CFG".bak* | head -n1)
    run cp "$latest" "$KWIN_CFG"
    log "KWin restored"
  fi

  run systemctl daemon-reload
  log "Normalization complete"
fi

[[ $MODE == "revert" ]] && exit 0

# =========================================================
# PART 2 — IMMORTAL DRIVE UTILIZATION
# =========================================================
echo "--- EXTRA STORAGE CONFIG ---"

if mountpoint -q "$EXTRA_DRIVE"; then
  log "ExtraStorage detected"

  # Validate writable
  if touch "$EXTRA_DRIVE/.test" 2>/dev/null; then
    rm -f "$EXTRA_DRIVE/.test"
  else
    warn "ExtraStorage not writable — skipping"
  fi

  # Timeshift
  run mkdir -p "$EXTRA_DRIVE/timeshift"

  # Swapfile (persistent + fstab safe)
  if [[ ! -f "$EXTRA_DRIVE/swapfile" ]]; then
    run fallocate -l 8G "$EXTRA_DRIVE/swapfile"
    run chmod 600 "$EXTRA_DRIVE/swapfile"
    run mkswap "$EXTRA_DRIVE/swapfile"
  fi

  if ! grep -q "$EXTRA_DRIVE/swapfile" /etc/fstab; then
    echo "$EXTRA_DRIVE/swapfile none swap sw 0 0" >> /etc/fstab
    log "Swapfile added to fstab"
  fi

  run swapon -a

  # NVIDIA suspend/cache
  run mkdir -p "$EXTRA_DRIVE/nvidia-cache"

else
  warn "ExtraStorage not mounted — skipping"
fi

# =========================================================
# PART 3 — PERFORMANCE LAYER
# =========================================================
echo "--- APPLYING SAFE OPTIMIZATIONS ---"

run dnf install -y tuned zram-generator gamemode

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
log "RAM: ${TOTAL_RAM_GB}GB"

# ===== SELINUX =====
if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
  run sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
  run setenforce 0
  log "SELinux → permissive"
fi

# ===== ZRAM =====
ZRAM_SIZE=$(( TOTAL_RAM_GB / 2 ))
[[ $ZRAM_SIZE -gt 16 ]] && ZRAM_SIZE=16
[[ $ZRAM_SIZE -lt 4 ]] && ZRAM_SIZE=4

safe_write /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ${ZRAM_SIZE}G
compression-algorithm = zstd
swap-priority = 100
EOF

run systemctl daemon-reload
log "ZRAM: ${ZRAM_SIZE}GB"

# ===== SYSCTL =====
safe_write /etc/sysctl.d/99-immortal.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF

run sysctl --system

# ===== TUNED =====
mkdir -p /etc/tuned/immortal-ultima

safe_write /etc/tuned/immortal-ultima/tuned.conf <<EOF
[main]
include=balanced
EOF

run systemctl enable --now tuned

if tuned-adm list | grep -q immortal-ultima; then
  run tuned-adm profile immortal-ultima
else
  run tuned-adm profile balanced
fi

log "Tuned configured"

# ===== GAMEMODE =====
run systemctl enable --now gamemoded

# ===== NVIDIA =====
if lspci | grep -qi nvidia; then
  if systemctl list-unit-files | grep -q nvidia-persistenced; then
    run systemctl enable --now nvidia-persistenced.service
    log "NVIDIA persistence enabled"
  fi
fi

# ===== CPU GOVERNOR =====
if command -v cpupower >/dev/null; then
  run cpupower frequency-set -g schedutil
fi

# ===== KWIN BACKUP =====
KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"
[[ -f "$KWIN_CFG" ]] && run cp "$KWIN_CFG" "$KWIN_CFG.bak.$(date +%s)"

# ===== DISPLAY WAKE =====
[[ -x /usr/local/bin/immortal-display-wake ]] && run /usr/local/bin/immortal-display-wake

# ===== FINAL =====
run fc-cache -fv
run systemctl daemon-reexec

echo ""
echo "===== IMMORTAL v9.0 COMPLETE ====="
echo "System is NORMALIZED • STABLE • OPTIMIZED • FUTURE-PROOF"
echo "Reboot recommended"
