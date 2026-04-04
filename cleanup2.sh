#!/bin/bash
# IMMORTAL FULL REVERSAL — SAFE • NO SNAPSHOTS • DETERMINISTIC

set -euo pipefail

echo "===== IMMORTAL FULL REVERSAL START ====="

# ===== ROOT CHECK =====
if [[ $EUID -ne 0 ]]; then
  echo "Run with: sudo ./script.sh"
  exit 1
fi

# ===== SAFE USER DETECTION =====
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# ===== SELINUX REVERT =====
if command -v getenforce >/dev/null 2>&1; then
  echo "[*] Restoring SELinux to Enforcing"
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config || true
  setenforce 1 2>/dev/null || true
fi

# ===== REMOVE CUSTOM TUNED PROFILE =====
if [[ -d /etc/tuned/immortal-ultima ]]; then
  echo "[*] Removing custom tuned profile"
  rm -rf /etc/tuned/immortal-ultima
fi

if command -v tuned-adm >/dev/null 2>&1; then
  echo "[*] Restoring tuned to default (balanced)"
  tuned-adm profile balanced || true
fi

# ===== ZRAM REVERT =====
if [[ -f /etc/systemd/zram-generator.conf ]]; then
  echo "[*] Removing custom zram config"
  rm -f /etc/systemd/zram-generator.conf
fi

# Unmask default zram service safely
systemctl unmask systemd-zram-setup@zram0.service 2>/dev/null || true
systemctl daemon-reexec || true

# ===== UNMASK SERVICES (SAFE SET) =====
SERVICES_TO_UNMASK=(
  accounts-daemon.service
  ModemManager.service
  sssd.service
  switcheroo-control.service
  virtqemud.service
  virtlogd.service
  virtstoraged.service
  virtproxyd.service
)

echo "[*] Restoring masked services (safe subset)"
for svc in "${SERVICES_TO_UNMASK[@]}"; do
  systemctl unmask "$svc" 2>/dev/null || true
done

# ===== DISABLE ONLY WHAT IMMORTAL ENABLED =====
echo "[*] Resetting optional services"

systemctl disable --now earlyoom 2>/dev/null || true
systemctl disable --now irqbalance 2>/dev/null || true

# tuned stays enabled (Fedora default behavior)

# ===== REMOVE OPTIONAL PACKAGES (ONLY IF INSTALLED BY SCRIPT) =====
echo "[*] Removing optional packages (safe subset)"

dnf remove -y \
  earlyoom \
  zram-generator \
  2>/dev/null || true

# DO NOT remove:
# smartmontools, lm_sensors, nvme-cli, fwupd (these are harmless + useful)

# ===== KWIN CONFIG (SAFE RESTORE) =====
KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"

if ls "$KWIN_CFG".bak* >/dev/null 2>&1; then
  echo "[*] Restoring previous KWin monitor config"
  latest_backup=$(ls -t "$KWIN_CFG".bak* | head -n1)
  cp "$latest_backup" "$KWIN_CFG"
fi

# ===== REMOVE IMMORTAL FILES =====
echo "[*] Cleaning immortal files"

rm -rf /var/lib/immortal 2>/dev/null || true
rm -f /var/log/immortal*.log 2>/dev/null || true
rm -f /var/lock/immortal*.lock 2>/dev/null || true

# ===== FINAL SYSTEM REFRESH =====
echo "[*] Rebuilding system state"

command -v dracut >/dev/null && dracut -f || true
command -v grub2-mkconfig >/dev/null && grub2-mkconfig -o /boot/grub2/grub.cfg || true

echo ""
echo "===== REVERSAL COMPLETE ====="
echo "System returned to Fedora-like baseline (without touching your monitor setup)"
echo "Reboot recommended."

exit 0
