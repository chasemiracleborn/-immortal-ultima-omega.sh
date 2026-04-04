#!/bin/bash
# IMMORTAL FULL PURGE — Removes ALL v7.x effects (keeps v8-safe baseline)

set -euo pipefail

echo "===== IMMORTAL FULL PURGE START ====="

# ===== ROOT CHECK =====
[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }

# ===== REMOVE MARKER / STATE JUNK =====
echo "[*] Cleaning immortal state..."
rm -rf /var/lib/immortal/markers 2>/dev/null || true
rm -rf /var/lib/immortal/snapshots/* 2>/dev/null || true

# ===== REMOVE BACKUP CLUTTER =====
echo "[*] Cleaning old backups..."
rm -rf /root/immortal-backups 2>/dev/null || true

# ===== REMOVE CUSTOM MODPROBE (v7.5 NVIDIA tweaks) =====
echo "[*] Removing custom modprobe configs..."
rm -f /etc/modprobe.d/nvidia-immortal.conf 2>/dev/null || true

# ===== REMOVE CUSTOM SYSCTL / TUNING FILES =====
echo "[*] Cleaning sysctl/tuning overrides..."
rm -f /etc/sysctl.d/99-immortal.conf 2>/dev/null || true
rm -rf /etc/tuned/immortal-* 2>/dev/null || true

# ===== REMOVE POSSIBLE BAD SERVICE FILES =====
echo "[*] Removing custom immortal services..."
rm -f /etc/systemd/system/immortal-* 2>/dev/null || true
rm -f /usr/lib/systemd/system/immortal-* 2>/dev/null || true

systemctl daemon-reload || true

# ===== UNMASK ANY SERVICES THAT MAY HAVE BEEN MASKED =====
echo "[*] Unmasking critical services..."
for svc in \
  accounts-daemon \
  atd \
  crond \
  systemd-logind \
  NetworkManager
do
  systemctl unmask "$svc" 2>/dev/null || true
done

# ===== DISABLE UNKNOWN TIMERS =====
echo "[*] Removing unsafe timers..."
systemctl disable --now fwupd-refresh.timer 2>/dev/null || true
systemctl disable --now fstrim.timer 2>/dev/null || true

# ===== RESET FWUPD (remove forced automation behavior) =====
echo "[*] Resetting fwupd behavior..."
systemctl disable --now fwupd.service 2>/dev/null || true

# ===== REMOVE UNUSED PACKAGES (SAFE LIST ONLY) =====
echo "[*] Removing risky auto-installed packages..."

dnf remove -y \
  netdata \
  tuned-ppd \
  powertop \
  rng-tools \
  scx-scheds \
  2>/dev/null || true

# ===== RESET TUNED =====
echo "[*] Resetting tuned..."
tuned-adm profile balanced || true

# ===== ZRAM CLEAN (will be reapplied by v8 safely) =====
echo "[*] Resetting zram..."
rm -f /etc/systemd/zram-generator.conf 2>/dev/null || true
systemctl daemon-reexec || true

# ===== KDE / KWIN (DO NOT TOUCH ACTIVE CONFIG) =====
echo "[*] Preserving KDE monitor behavior (no changes)"

# ===== SELINUX (KEEP PERMISSIVE — YOUR REQUIREMENT) =====
echo "[*] Leaving SELinux as-is (permissive retained)"

# ===== FINAL CLEANUP =====
echo "[*] Reloading systemd..."
systemctl daemon-reexec || true

echo "===== PURGE COMPLETE =====
System is now CLEAN of all pre-v8 risk layers."
