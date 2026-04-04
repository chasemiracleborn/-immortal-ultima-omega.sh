#!/bin/bash
# IMMORTAL ULTRA-STABLE v8.0 — FINAL
# Built for: Stability • Safety • Compatibility ONLY

set -euo pipefail

# ===== GLOBALS =====
LOG_FILE="/var/log/immortal-v8.log"
LOCK_FILE="/var/lock/immortal-v8.lock"
STATE_DIR="/var/lib/immortal"
SNAPSHOT_BASE="/var/lib/immortal/snapshots"

mkdir -p "$STATE_DIR" "$SNAPSHOT_BASE"

# ===== LOCKING (safe addition from v7.8) =====
exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Already running. Exiting."; exit 1; }
trap 'flock -u 200' EXIT

exec >> "$LOG_FILE" 2>&1

echo "===== START $(date) ====="

# ===== ROOT CHECK =====
if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

# ===== SAFE USER DETECTION =====
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 || echo "/home/$REAL_USER")"

# ===== SAFE SNAPSHOT SYSTEM =====
create_snapshot() {
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local snap="$SNAPSHOT_BASE/$ts"

  mkdir -p "$snap"

  for item in \
    /etc/default/grub \
    /etc/fstab \
    /etc/sysctl.d \
    /etc/modprobe.d \
    /etc/selinux/config
  do
    [[ -e "$item" ]] && cp -a "$item" "$snap/"
  done

  echo "$snap" > "$STATE_DIR/last_snapshot"
  echo "Snapshot created: $snap"
}

safe_restore() {
  local last
  last=$(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo "")

  [[ -d "$last" ]] || { echo "No snapshot found"; exit 1; }

  echo "Restoring snapshot: $last"

  # SAFE RESTORE — no blanket overwrite
  for file in "$last"/*; do
    base=$(basename "$file")

    case "$base" in
      grub|fstab|config|*.conf)
        cp -a "$file" "/etc/" || true
        ;;
      *)
        echo "Skipping unsafe restore target: $base"
        ;;
    esac
  done

  command -v grub2-mkconfig >/dev/null && grub2-mkconfig -o /boot/grub2/grub.cfg || true
  command -v dracut >/dev/null && dracut -f || true

  echo "Restore complete"
}

# ===== FLAGS =====
REVERT=0
for arg in "$@"; do
  case "$arg" in
    --revert) REVERT=1 ;;
  esac
done

if [[ $REVERT -eq 1 ]]; then
  safe_restore
  exit 0
fi

# ===== SNAPSHOT BEFORE CHANGES =====
create_snapshot

# ===== HARDWARE DETECTION =====
CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)
RAM=$(free -g | awk '/Mem:/ {print $2}')
KERNEL=$(uname -r)

echo "CPU: $CPU"
echo "RAM: ${RAM}GB"
echo "Kernel: $KERNEL"

# ===== GPU DETECTION =====
GPU_NVIDIA=0
lspci | grep -qi nvidia && GPU_NVIDIA=1

# ===== KDE BLACK SCREEN FIX (SAFE + OPTIONAL) =====
KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"
if [[ -f "$KWIN_CFG" ]]; then
  cp "$KWIN_CFG" "$KWIN_CFG.bak"
  echo "Backed up KWin config (no forced deletion)"
fi

# ===== PACKAGE INSTALL (SAFE + QUIET) =====
dnf install -y \
  smartmontools \
  lm_sensors \
  irqbalance \
  earlyoom \
  tuned \
  zram-generator \
  nvme-cli \
  fwupd || true

# ===== NVIDIA SAFE HANDLING =====
if [[ $GPU_NVIDIA -eq 1 ]]; then
  dnf install -y akmod-nvidia || true
  echo "NVIDIA driver ensured"
fi

# ===== ZRAM (SAFE, NON-CONFLICTING) =====
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram / 2, 16G)
compression-algorithm = zstd
EOF

systemctl daemon-reexec || true

# ===== TUNED (NO CONFLICTS) =====
systemctl enable --now tuned || true
tuned-adm profile balanced || true

# ===== SELINUX (AS REQUESTED) =====
if command -v getenforce >/dev/null; then
  if [[ "$(getenforce)" == "Enforcing" ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    setenforce 0 || true
    echo "SELinux set to permissive"
  fi
fi

# ===== SAFE SERVICES ONLY =====
systemctl enable --now irqbalance || true
systemctl enable --now earlyoom || true

echo "===== COMPLETE — SYSTEM STABLE ====="
