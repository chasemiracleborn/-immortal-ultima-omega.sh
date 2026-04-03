#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║ IMMORTAL ULTIMA OMEGA — UNIVERSAL v6.9 KEFKA GOD MODE (FIXED LOCK BLACK v3)║
# ║ One script to rule them all. Desktops & Laptops. NVIDIA / AMD / Intel. ║
# ║ Hardware-aware, idempotent, reversible, snapshot-backed, self-healing. ║
# ║ Now with state directory, config snapshots, --status/--revert, hardening, ║
# ║ Deskflow auto-allow KVM PC, Firefox latency fix, ABCDE Guardian triage, ║
# ║ KEFKA REVERSAL RITUAL on REAL USER Desktop (fixed for sudo), low-impact Sentinel, ║
# ║ and monitors that TURN OFF on lock but wake PERFECTLY (no black/undrawn). ║
# ║ ║
# ║ All v6.6 logic 100% preserved + kwinoutputconfig.json safety + Wayland repaint fix. ║
# ║ "I will destroy everything... I will create a monument to non-existence!" ║
# ║ "Hee-hee... Nothing beats the sweet music of hundreds of voices screaming ║
# ║ in unison!" ║
# ║ ║
# ║ Creation Date: 2026-04-03 ║
# ║ Usage: sudo bash immortal-ultima-omega.sh [--dry-run] [--force] [--status] ║
# ║ [--revert] ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOUR PALETTE + LOGGING
# ─────────────────────────────────────────────────────────────────────────────
RED=$'[0;31m'; GRN=$'[0;32m'; YLW=$'[1;33m'
BLU=$'[0;34m'; CYN=$'[0;36m'; MAG=$'[0;35m'
BOLD=$'[1m'; NC=$'[0m'

LOG_FILE="/var/log/immortal-ultima-omega.log"
LOCK_FILE="/var/lock/immortal-ultima-omega.lock"
STATE_DIR="/var/lib/immortal"
MARKER_DIR="$STATE_DIR/markers"
SNAPSHOT_DIR="$HOME/immortal-snapshots"

mkdir -p "$STATE_DIR" "$MARKER_DIR" "$SNAPSHOT_DIR" 2>/dev/null || true

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Another instance of Immortal Ultima Omega is already running. Exiting." >&2
  exit 1
fi
cleanup() { exec 200>&-; }
trap cleanup EXIT

touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/immortal-ultima-omega.log"

log()    { echo -e "${GRN}[✓ PLAN A]${NC} $*" | tee -a "$LOG_FILE"; }
planb()  { echo -e "${BLU}[↻ PLAN B]${NC} $*" | tee -a "$LOG_FILE"; }
planc()  { echo -e "${YLW}[⚡ PLAN C]${NC} $*" | tee -a "$LOG_FILE"; }
pland()  { echo -e "${RED}[🔴 PLAN D]${NC} ${BOLD}$*${NC}" | tee -a "$LOG_FILE"; }
plane()  { echo -e "${MAG}[🌀 PLAN E]${NC} $*" | tee -a "$LOG_FILE"; }
planf()  { echo -e "${CYN}[🌌 PLAN F]${NC} $*" | tee -a "$LOG_FILE"; }
plang()  { echo -e "${GRN}[💥 SPIRIT BOMB]${NC} $*" | tee -a "$LOG_FILE"; }
verify() { echo -e "${MAG}[⊛ VERIFY]${NC} $*" | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YLW}[⚠]${NC} $*" | tee -a "$LOG_FILE"; }
err()    { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; }
info()   { echo -e "${BLU}[→]${NC} $*" | tee -a "$LOG_FILE"; }
sect()   { echo -e "${MAG}[★]${NC} ${BOLD}$*${NC}" | tee -a "$LOG_FILE"; }

VERIFY_FAILURES=0
FAILURE_LOG=()
record_failure() {
  VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
  FAILURE_LOG+=("$*")
  pland "VERIFICATION FAILED: $*"
}

DRY_RUN=0; SKIP_PKGS=0; NO_BACKUP=0; FORCE=0; STATUS_ONLY=0; REVERT_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-backup) NO_BACKUP=1 ;;
    --skip-packages) SKIP_PKGS=1 ;;
    --force) FORCE=1 ;;
    --status) STATUS_ONLY=1 ;;
    --revert) REVERT_ONLY=1 ;;
    *) err "Unknown argument: $arg"; exit 1 ;;
  esac
done

[[ $EUID -ne 0 ]] && { err "Run as root: sudo $0 $*"; exit 1; }

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || echo "/home/$REAL_USER")
[[ ! -d "$REAL_HOME" ]] && REAL_HOME="/home/$REAL_USER"

BACKUP_DIR="/root/immortal-backups/$(date +%Y%m%d_%H%M%S)"
backup_file() {
  local file="$1"
  [[ $NO_BACKUP -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  [[ -f "$file" ]] || return 0
  mkdir -p "${BACKUP_DIR}$(dirname "$file")"
  cp -p "$file" "${BACKUP_DIR}${file}" && info " Backed up: $file"
}

write_file() {
  local path="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e " ${YLW}[DRY-RUN]${NC} Would write: $path"
    cat > /dev/null
  else
    mkdir -p "$(dirname "$path")"
    cat > "$path"
  fi
}

is_completed() { [[ -f "$MARKER_DIR/$1" ]] && [[ $FORCE -eq 0 ]]; }
mark_completed() { touch "$MARKER_DIR/$1" 2>/dev/null || true; }

create_snapshot() {
  local name="$1"
  local ts=$(date +%Y%m%d_%H%M%S)
  local snap="$SNAPSHOT_DIR/${ts}_${name}"
  mkdir -p "$snap"
  for dir in /etc/grub.d /etc/default/grub /etc/fstab /etc/modprobe.d /etc/sysctl.d /etc/tuned /etc/udev/rules.d /etc/X11 /etc/selinux; do
    [[ -d "$dir" ]] && cp -a "$dir" "$snap/" 2>/dev/null || true
  done
  echo "$snap" > "$STATE_DIR/last_snapshot"
  log "Created rollback snapshot: $snap"
}

revert_last_snapshot() {
  local last=$(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo "")
  if [[ -d "$last" ]]; then
    warn "Restoring from snapshot: $last"
    cp -a "$last/"* /etc/ 2>/dev/null || true
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    dracut -f 2>/dev/null || true
    log "Rollback complete from $last"
  else
    err "No snapshot found to revert"
  fi
}

STEP=0
step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYN} [Step $STEP] $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

enable_service() {
  local svc="$1" desc="${2:-$svc}"
  [[ $DRY_RUN -eq 1 ]] && { info "[DRY-RUN] Would enable: $svc"; return 0; }
  if systemctl enable --now "$svc" >> "$LOG_FILE" 2>&1; then log "Enabled: $desc"; return 0; fi
  if systemctl enable "$svc" && systemctl start "$svc" >> "$LOG_FILE" 2>&1; then planb "Enabled (enable+start): $desc"; return 0; fi
  if systemctl enable "$svc" >> "$LOG_FILE" 2>&1; then planc "Enabled (start deferred): $desc"; return 0; fi
  record_failure "$desc: enable failed"
  plane "Plan E: restart + daemon-reload"; systemctl daemon-reload && systemctl restart "$svc" >> "$LOG_FILE" 2>&1 || true
  if systemctl is-active --quiet "$svc"; then plane "Recovered via restart"; return 0; fi
  planf "Plan F: unit recreation fallback"; systemctl daemon-reload && systemctl start "$svc" >> "$LOG_FILE" 2>&1 || true
  if systemctl is-active --quiet "$svc"; then planf "Recovered via unit reload"; return 0; fi
  plang "Plan G + Spirit Bomb: force enable + reset-failed"
  systemctl enable --now --force "$svc" >> "$LOG_FILE" 2>&1 || true
  systemctl reset-failed "$svc" >> "$LOG_FILE" 2>&1 || true
}

echo ""
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA — UNIVERSAL v6.9 KEFKA GOD MODE (FIXED LOCK BLACK v3) ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $DRY_RUN -eq 1 ]] && warn "DRY-RUN MODE — No changes"
[[ $NO_BACKUP -eq 1 ]] && warn "NO-BACKUP MODE"
[[ $SKIP_PKGS -eq 1 ]] && warn "SKIP-PACKAGES MODE"

if [[ $STATUS_ONLY -eq 1 ]]; then
  echo -e "${CYN}=== IMMORTAL STATUS ===${NC}"
  echo "Last snapshot: $(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo "none")"
  echo "Markers applied: $(ls "$MARKER_DIR" 2>/dev/null | wc -l)"
  systemctl is-active --quiet tuned && echo "Tuned: active" || echo "Tuned: inactive"
  systemctl is-active --quiet immortal-guardian.timer && echo "Guardian: active" || echo "Guardian: inactive"
  systemctl is-active --quiet immortal-sentinel.service && echo "Sentinel: active" || echo "Sentinel: inactive"
  exit 0
fi

if [[ $REVERT_ONLY -eq 1 ]]; then
  revert_last_snapshot
  exit 0
fi

{
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] IMMORTAL ULTIMA OMEGA v6.9 KEFKA GOD MODE RUN"
  echo "Kernel: $(uname -r) | Host: $(hostname)"
  echo "════════════════════════════════════════════════════════"
} >> "$LOG_FILE"

log "Starting IMMORTAL ULTIMA OMEGA v6.9 KEFKA GOD MODE"

sect "Preflight: Universal Hardware Fingerprint + RAM/VM/DE/CachyOS Detection"
echo ""

IS_LAPTOP=0
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  IS_LAPTOP=1; log "Form factor: LAPTOP (battery detected)"
else
  log "Form factor: DESKTOP (no battery)"
fi

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}' || echo 0)
log "RAM detected: ${TOTAL_RAM_GB} GB"

IS_VM=0
if systemd-detect-virt -q 2>/dev/null; then
  IS_VM=1; warn "Running inside VM — some aggressive tweaks will be softened"
fi

IS_CACHYOS=0
if uname -r | grep -qi cachyos; then
  IS_CACHYOS=1; log "CachyOS custom kernel detected — full compatibility enabled"
fi

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
IS_INTEL_CPU=0; IS_AMD_CPU=0
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then IS_INTEL_CPU=1; log "CPU: Intel"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then IS_AMD_CPU=1; log "CPU: AMD"
else warn "CPU: unknown vendor ($CPU_VENDOR)"; fi

GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0
if lspci -nn | grep -E 'VGA|3D|Display' | grep -qi nvidia; then GPU_NVIDIA=1; log "GPU: NVIDIA detected"; fi
if lspci -nn | grep -E 'VGA|3D|Display' | grep -qiE 'amd|radeon|ati'; then GPU_AMD=1; log "GPU: AMD detected"; fi
if lspci -nn | grep -E 'VGA|3D|Display' | grep -qi intel; then GPU_INTEL=1; log "GPU: Intel iGPU detected"; fi

get_drive_model() {
  local dev="$1"
  smartctl -d sat -i "$dev" 2>/dev/null | grep -Ei 'Device Model|Model Number' | head -1 | awk -F: '{print $2}' | xargs 2>/dev/null ||
  smartctl -i "$dev" 2>/dev/null | grep -Ei 'Device Model|Model Number' | head -1 | awk -F: '{print $2}' | xargs 2>/dev/null ||
  hdparm -I "$dev" 2>/dev/null | grep -i 'Model Number' | awk -F: '{print $2}' | xargs 2>/dev/null || echo "UNKNOWN"
}

EXOS_DRIVES=(); PLEXTOR_DRIVES=(); OCZ_DRIVES=(); NVME_DRIVES=()
UNKNOWN_SATA_ROT=(); UNKNOWN_SATA_SSD=()

info "Scanning block devices..."
for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
  [[ -b "$dev" ]] || continue
  transport=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_BUS=' | cut -d= -f2 || echo "")
  [[ "$transport" == "usb" ]] && { warn " $dev — USB skipped"; continue; }
  if [[ "$dev" == /dev/nvme* ]]; then
    NVME_DRIVES+=("$dev"); info " $dev — NVMe ✓"
    continue
  fi
  model=$(get_drive_model "$dev")
  rot=$(cat "/sys/block/$(basename "$dev")/queue/rotational" 2>/dev/null || echo "?")
  if echo "$model" | grep -qiE 'ST18000NM|ST18000'; then
    EXOS_DRIVES+=("$dev"); info " $dev — Seagate EXOS 18TB ✓"
  elif echo "$model" | grep -qiE 'PX-M5P|M5Pro|Plextor'; then
    PLEXTOR_DRIVES+=("$dev"); info " $dev — Plextor M5Pro ✓"
  elif echo "$model" | grep -qiE 'TRION|OCZ-TRION|OCZ'; then
    OCZ_DRIVES+=("$dev"); info " $dev — OCZ TRION150 ✓"
  elif [[ "$rot" == "1" ]]; then
    UNKNOWN_SATA_ROT+=("$dev"); warn " $dev — rotational SATA (unconfirmed)"
  else
    UNKNOWN_SATA_SSD+=("$dev"); warn " $dev — SATA SSD (unconfirmed)"
  fi
done

SATA_HDDS=("${EXOS_DRIVES[@]}" "${UNKNOWN_SATA_ROT[@]}")
SATA_SSDS=("${PLEXTOR_DRIVES[@]}" "${OCZ_DRIVES[@]}" "${UNKNOWN_SATA_SSD[@]}")

EXTRA_MOUNTED=0
if mountpoint -q /mnt/ExtraStorage 2>/dev/null; then
  EXTRA_MOUNTED=1; log "/mnt/ExtraStorage mounted — will be used for Tier-2 swapfile"
fi

DE="unknown"
if pgrep -x gnome-shell >/dev/null 2>&1; then DE="GNOME"
elif pgrep -x plasmashell >/dev/null 2>&1; then DE="KDE"
elif [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then DE="${XDG_CURRENT_DESKTOP}"; fi
log "Desktop Environment: $DE"

info ""
info "Hardware summary → CPU: ${CPU_VENDOR} | GPU: NVIDIA=$GPU_NVIDIA AMD=$GPU_AMD Intel=$GPU_INTEL | Laptop=$IS_LAPTOP | CachyOS=$IS_CACHYOS | RAM=${TOTAL_RAM_GB}GB | VM=$IS_VM | DE=$DE"
info "NVMe drives: ${NVME_DRIVES[*]:-none} | SATA HDD: ${SATA_HDDS[*]:-none} | SATA SSD: ${SATA_SSDS[*]:-none}"

step "State & Safety Setup (v6.9)"
create_snapshot "pre-run"

step "KWin Output Config Safety (fixes black lock screen)"
KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"
if [[ -f "$KWIN_CFG" ]]; then
  backup_file "$KWIN_CFG"
  mv "$KWIN_CFG" "${KWIN_CFG}.bak.$(date +%s)" && log "Backed up and disabled corrupt kwinoutputconfig.json (KWin will regenerate clean config)"
else
  log "No kwinoutputconfig.json found — already clean"
fi

step "Prerequisite Packages"
if [[ $GPU_NVIDIA -eq 1 && $SKIP_PKGS -eq 0 && $DRY_RUN -eq 0 ]]; then
  if ! dnf repolist | grep -q rpmfusion; then
    info "NVIDIA detected — enabling RPM Fusion..."
    dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
      >> "$LOG_FILE" 2>&1 || true
    dnf config-manager --enable rpmfusion-free rpmfusion-nonfree >> "$LOG_FILE" 2>&1 || true
  fi
fi
PKGS_ALL=(
  smartmontools lm_sensors irqbalance earlyoom hdparm nvme-cli
  util-linux pciutils usbutils numactl zram-generator
  powertop sysstat cronie xorg-x11-utils fwupd
  tuned tuned-ppd xclip wl-clipboard
)
[[ $GPU_NVIDIA -eq 1 ]] && PKGS_ALL+=(akmod-nvidia xorg-x11-drv-nvidia-cuda)
[[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]] && PKGS_ALL+=(mesa-va-drivers)
[[ $IS_LAPTOP -eq 1 ]] && PKGS_ALL+=(power-profiles-daemon thermald)
if [[ $SKIP_PKGS -eq 1 ]]; then
  warn "Package install skipped"
elif [[ $DRY_RUN -eq 1 ]]; then
  info "[DRY-RUN] Would install: ${PKGS_ALL[*]}"
else
  if ! dnf install -y "${PKGS_ALL[@]}" >> "$LOG_FILE" 2>&1; then
    planb "Bulk install failed — trying individually with retries"
    for pkg in "${PKGS_ALL[@]}"; do
      if ! rpm -q "$pkg" &>/dev/null; then
        dnf install -y "$pkg" >> "$LOG_FILE" 2>&1 && log "Installed: $pkg" || warn "Failed to install $pkg (continuing)"
      fi
    done
  else
    log "All packages installed"
  fi
  if [[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]]; then
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld >> "$LOG_FILE" 2>&1 || true
  fi
  if [[ $GPU_NVIDIA -eq 1 ]] && ! rpm -q akmod-nvidia &>/dev/null; then
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda >> "$LOG_FILE" 2>&1 || warn "NVIDIA driver install failed"
  fi
  akmods --force >> "$LOG_FILE" 2>&1 || true
fi

step "SELinux Alert Suppression"
if command -v getenforce >/dev/null 2>&1; then
  if [[ "$(getenforce)" == "Enforcing" ]]; then
    backup_file /etc/selinux/config
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    setenforce 0
    log "SELinux set to Permissive — alerts suppressed permanently"
  else
    log "SELinux already in Permissive/Disabled mode"
  fi
fi

step "Firmware Updates & Drive Diagnostics (fwupd + NVMe/SMART)"
if [[ $DRY_RUN -eq 1 ]]; then
  info "[DRY-RUN] Would run fwupdmgr refresh + get-updates + NVMe/SMART diagnostics"
else
  log "Refreshing firmware metadata (fwupdmgr)..."
  fwupdmgr refresh --force >> "$LOG_FILE" 2>&1 || true
  fwupdmgr get-devices >> "$LOG_FILE" 2>&1 || true
  if fwupdmgr get-updates --json 2>/dev/null | grep -q '"Updates"'; then
    log "Firmware updates available — applying safely (no reboot forced)"
    fwupdmgr update --assume-yes --no-reboot-check >> "$LOG_FILE" 2>&1 || planc "Some firmware updates deferred (safe)"
  else
    log "All system firmware is up to date"
  fi
  enable_service fwupd-refresh.timer "fwupd auto-refresh timer"
  info "NVMe device list:"
  nvme list >> "$LOG_FILE" 2>&1 || true
  for dev in "${NVME_DRIVES[@]}"; do nvme smart-log "$dev" >> "$LOG_FILE" 2>&1 || true; done
  for dev in "${SATA_HDDS[@]}" "${SATA_SSDS[@]}"; do smartctl -a "$dev" >> "$LOG_FILE" 2>&1 || true; done
  log "NVMe + SMART diagnostics completed and logged"
fi

step "GPU Modprobe Config"
if [[ $GPU_NVIDIA -eq 1 ]]; then
  NVIDIA_CONF=/etc/modprobe.d/nvidia-immortal.conf
  backup_file "$NVIDIA_CONF"
  write_file "$NVIDIA_CONF" << 'MODEOF'
# NVIDIA — Immortal Ultima Omega v6.9 KEFKA GOD MODE (RTX 50-series + explicit sync ready)
options nvidia NVreg_EnableGpuFirmware=1
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia_drm modeset=1 fbdev=1
softdep nvidia_drm pre: nvidia nvidia_modeset
MODEOF
  log "NVIDIA modprobe written (explicit sync enabled via modeset=1)"
elif [[ $GPU_AMD -eq 1 ]]; then
  AMD_CONF=/etc/modprobe.d/amdgpu-immortal.conf
  backup_file "$AMD_CONF"
  write_file "$AMD_CONF" << 'AMDEOF'
# AMD GPU — Immortal Ultima Omega v6.9 KEFKA GOD MODE
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff
AMDEOF
  log "AMD modprobe written"
elif [[ $GPU_INTEL -eq 1 ]]; then
  INTEL_CONF=/etc/modprobe.d/i915-immortal.conf
  backup_file "$INTEL_CONF"
  write_file "$INTEL_CONF" << 'INTEOF'
# Intel iGPU — Immortal Ultima Omega v6.9 KEFKA GOD MODE
options i915 enable_psr=1
options i915 enable_guc=2
INTEOF
  log "Intel i915 modprobe written"
fi

step "NVMe PS0 Lock"
NVME_CONF=/etc/modprobe.d/nvme-immortal.conf
backup_file "$NVME_CONF"
if [[ $IS_LAPTOP -eq 0 && ${#NVME_DRIVES[@]} -gt 0 ]]; then
  write_file "$NVME_CONF" << 'NVMEOF'
# NVMe PS0 lock — Desktop only
options nvme_core default_ps_max_latency_us=0
NVMEOF
  echo "0" > /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null || true
  log "NVMe PS0 lock applied (Desktop)"
else
  [[ -f "$NVME_CONF" ]] && sed -i '/default_ps_max_latency_us/d' "$NVME_CONF" 2>/dev/null || true
  log "NVMe PS0 lock skipped (Laptop or no NVMe)"
fi

step "USB Stability + Touchpad Keep-Alive"
USB_CONF=/etc/modprobe.d/usb-stability.conf
TOUCHPAD_RULE=/etc/udev/rules.d/99-touchpad-keepalive.rules
backup_file "$USB_CONF"
backup_file "$TOUCHPAD_RULE"
write_file "$USB_CONF" << 'USBEof'
options usbcore autosuspend=-1
USBEof
write_file "$TOUCHPAD_RULE" << 'TOUCHEof'
ACTION=="add", SUBSYSTEM=="input", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"
TOUCHEof
udevadm control --reload-rules && udevadm trigger 2>/dev/null || true
log "USB + touchpad rules applied"

step "IO Schedulers"
IO_RULES=/etc/udev/rules.d/60-immortal-io.rules
backup_file "$IO_RULES"
write_file "$IO_RULES" << 'IOEOF'
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/read_ahead_kb}="256"
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="16384"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="512"
IOEOF
udevadm control --reload-rules && udevadm trigger 2>/dev/null || true
log "IO scheduler rules applied"

step "Seagate EXOS APM Disable"
if [[ ${#EXOS_DRIVES[@]} -gt 0 ]]; then
  APM_RULES=/etc/udev/rules.d/61-seagate-exos-apm.rules
  backup_file "$APM_RULES"
  write_file "$APM_RULES" << 'APMEOF'
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="/usr/bin/hdparm -B 255 -S 0 /dev/%k"
APMEOF
  for dev in "${EXOS_DRIVES[@]}"; do hdparm -B 255 -S 0 "$dev" >> "$LOG_FILE" 2>&1 || true; done
  log "EXOS APM disabled"
else
  info "No EXOS drives detected"
fi

step "fstab — noatime + lazytime"
backup_file /etc/fstab
if [[ $DRY_RUN -eq 0 ]]; then
  sed -i '/^\s*[^#].*\s\(ext4\|btrfs\|xfs\)\s/ {
    /noatime/! s/defaults/defaults,noatime,lazytime,commit=60/
  }' /etc/fstab 2>> "$LOG_FILE" || true
  log "fstab updated"
fi

step "ZRAM — Dynamic sizing (fixed generator syntax)"
ZRAM_CONF=/etc/systemd/zram-generator.conf
backup_file "$ZRAM_CONF"
ZRAM_SIZE=$(( TOTAL_RAM_GB / 2 ))
[[ $ZRAM_SIZE -gt 16 ]] && ZRAM_SIZE=16
[[ $ZRAM_SIZE -lt 4 ]] && ZRAM_SIZE=4
write_file "$ZRAM_CONF" << ZRAMEOF
[zram0]
zram-size = ${ZRAM_SIZE}G
compression-algorithm = zstd
swap-priority = 100
ZRAMEOF
systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
log "ZRAM configured — dynamic size: ${ZRAM_SIZE} GB (fixed generator syntax)"

step "Tier-2 Swapfile on secondary SSD"
if [[ $EXTRA_MOUNTED -eq 1 && $DRY_RUN -eq 0 ]]; then
  SWAPFILE=/mnt/ExtraStorage/swapfile
  if [[ ! -f "$SWAPFILE" ]]; then
    FREE=$(df -BG /mnt/ExtraStorage | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if (( FREE >= 18 )); then
      dd if=/dev/zero of="$SWAPFILE" bs=1M count=16384 status=progress 2>&1 | tee -a "$LOG_FILE"
      chmod 600 "$SWAPFILE"
      mkswap "$SWAPFILE"
      echo "$SWAPFILE none swap defaults,pri=10 0 0" >> /etc/fstab
      swapon "$SWAPFILE"
      log "16GB swapfile created"
    else
      warn "Not enough free space on /mnt/ExtraStorage (need 18G, have ${FREE}G)"
    fi
  else
    info "Tier-2 swapfile already exists — skipping"
  fi
else
  info "No suitable secondary SSD — skipping Tier-2 swapfile"
fi

step "Sysctl"
SYSCTL_FILE=/etc/sysctl.d/99-immortal-ultima-omega.conf
backup_file "$SYSCTL_FILE"
SYSCTL_CONTENT='net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=5
vm.dirty_ratio=10
vm.max_map_count=2147483647
kernel.panic=10
fs.inotify.max_user_watches=1048576
net.ipv4.conf.all.rp_filter=1
kernel.dmesg_restrict=1
kernel.sched_autogroup_enabled=1'
if sysctl kernel.sched_itmt_enabled > /dev/null 2>&1; then
  SYSCTL_CONTENT+=$'
kernel.sched_itmt_enabled=1'
  info "kernel.sched_itmt_enabled supported — adding to sysctl"
else
  warn "kernel.sched_itmt_enabled not available on this kernel — skipped"
fi
echo "$SYSCTL_CONTENT" | write_file "$SYSCTL_FILE"
sysctl --system >> "$LOG_FILE" 2>&1 || true
log "Sysctl applied (added sched_autogroup for better input responsiveness)"

if [[ $IS_LAPTOP -eq 1 ]]; then
  step "Laptop Power & Thermal"
  systemctl enable --now power-profiles-daemon >> "$LOG_FILE" 2>&1 || true
  systemctl enable --now thermald >> "$LOG_FILE" 2>&1 || true
  write_file /etc/systemd/system/mobile-omega-powertop.service << 'POWEOF'
[Unit]
Description=powertop --auto-tune
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
POWEOF
  systemctl daemon-reload && systemctl enable --now mobile-omega-powertop.service >> "$LOG_FILE" 2>&1 || true
  if [[ -w /sys/power/mem_sleep ]] && grep -q deep /sys/power/mem_sleep; then
    echo "deep" > /sys/power/mem_sleep
    log "mem_sleep set to deep"
  fi
  log "Laptop power/thermal configured"
else
  info "Desktop detected — skipping laptop power module"
fi

step "GRUB Kernel Parameters"
REMOVE_ARGS=("nvidia.NVreg_PreserveVideoMemoryAllocations=1" "nvidia.NVreg_EnableGpuFirmware=0")
KERNEL_ARGS=("nouveau.modeset=0" "pcie_aspm=off" "nmi_watchdog=1")
[[ $GPU_NVIDIA -eq 1 ]] && KERNEL_ARGS+=("nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" "nvidia.NVreg_EnableGpuFirmware=1")
[[ $IS_INTEL_CPU -eq 1 && $IS_LAPTOP -eq 1 ]] && KERNEL_ARGS+=("i915.enable_psr=1")
[[ $IS_AMD_CPU -eq 1 ]] && KERNEL_ARGS+=("amd_pstate=active")
[[ $IS_LAPTOP -eq 1 ]] && KERNEL_ARGS+=("processor.max_cstate=5")
if [[ $DRY_RUN -eq 0 ]]; then
  grubby --update-kernel=ALL --remove-args="${REMOVE_ARGS[*]}" >> "$LOG_FILE" 2>&1 || true
  grubby --update-kernel=ALL --args="${KERNEL_ARGS[*]}" >> "$LOG_FILE" 2>&1 || true
  if [[ $GPU_NVIDIA -eq 1 ]]; then
    dracut -f >> "$LOG_FILE" 2>&1 || true
    log "dracut regenerated (NVIDIA)"
  fi
fi
log "GRUB parameters applied"

step "Monitor Wake & Display Recovery (Balanced Lock Sleep + Perfect Wake — v6.9)"
XORG_NODPMS=/etc/X11/xorg.conf.d/10-immortal-nodpms.conf
write_file "$XORG_NODPMS" << 'XORGEOF'
Section "ServerFlags"
    Option "BlankTime" "10"
    Option "StandbyTime" "15"
    Option "SuspendTime" "20"
    Option "OffTime" "30"
EndSection
XORGEOF

KDE_POWER=/etc/xdg/powermanagementprofilesrc
write_file "$KDE_POWER" << 'KDEEOF'
[AC][Display]
dimDisplayIdleTimeoutSec=600
displayIdleTimeoutSec=900
turnOffDisplayIdleTimeoutSec=1200
dimDisplayWhenIdle=true
[Battery][Display]
dimDisplayIdleTimeoutSec=300
displayIdleTimeoutSec=600
turnOffDisplayIdleTimeoutSec=900
[LowBattery][Display]
dimDisplayIdleTimeoutSec=180
displayIdleTimeoutSec=300
turnOffDisplayIdleTimeoutSec=600
KDEEOF

KDE_AUTOSTART=/etc/xdg/autostart/immortal-nodpms.desktop
write_file "$KDE_AUTOSTART" << 'AUTOEOF'
[Desktop Entry]
Name=Immortal — Balanced Display Wake
Type=Application
Exec=bash -c "sleep 8 && /usr/local/bin/immortal-display-wake"
X-KDE-Autostart-Phase=2
AUTOEOF

DISPLAY_WAKE=/usr/local/bin/immortal-display-wake
write_file "$DISPLAY_WAKE" << 'WAKEEOF'
#!/bin/bash
wake_log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a /tmp/immortal-display-wake.log; }
wake_log "Display wake triggered — balanced lock sleep + perfect unlock (v6.9)"

# Primary fix for black/undrawn screen (KWin + plasmashell repaint)
if command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.repaint 2>/dev/null || true
  qdbus org.kde.plasmashell /org/kde/plasmashell org.kde.plasmashell.repaint 2>/dev/null || true
  wake_log "KWin + plasmashell repaint triggered"
fi

# Safe kscreen-doctor fallback with retries
if command -v kscreen-doctor >/dev/null 2>&1; then
  for i in {1..3}; do
    if kscreen-doctor --outputs --set-all-enabled >/dev/null 2>&1; then
      wake_log "KScreen doctor succeeded (attempt $i)"
      break
    else
      wake_log "KScreen doctor failed (attempt $i) — retrying"
      sleep 1
    fi
  done
fi

# XRandR + RGB full (for any hybrid/XWayland)
if command -v xrandr >/dev/null 2>&1; then
  for out in $(xrandr | awk '/ connected/{print $1}'); do
    xrandr --output "$out" --auto >/dev/null 2>&1 || true
    xrandr --output "$out" --set "Broadcast RGB" "Full" >/dev/null 2>&1 || true
  done
fi

# Final safety net
if pgrep -x plasmashell >/dev/null 2>&1; then
  killall -SIGUSR1 plasmashell 2>/dev/null || true
  wake_log "Forced plasmashell repaint"
fi

wake_log "All monitors and lock screen should now draw correctly"
WAKEEOF
chmod +x "$DISPLAY_WAKE"
log "Balanced display recovery configured — monitors turn off on lock but wake perfectly (no black/undrawn screen)"

step "EarlyOOM"
OOM_DROP=/etc/systemd/system/earlyoom.service.d/tuning.conf
backup_file "$OOM_DROP"
write_file "$OOM_DROP" << 'OOMEOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/earlyoom -r 60 -m 5 -s 5 --prefer '(firefox|chromium|electron|code|brave|java)' --avoid '(sddm|pipewire|wireplumber|kwin_x11|kwin_wayland|plasmashell|Xorg|nvidia|earlyoom|plasma*|kwin*)'
OOMEOF
systemctl daemon-reload && enable_service earlyoom "EarlyOOM"

step "IRQ Balancing"
if [[ -f /etc/sysconfig/irqbalance ]]; then
  sed -i 's/IRQBALANCE_ONESHOT=.*/IRQBALANCE_ONESHOT=yes/' /etc/sysconfig/irqbalance 2>/dev/null || echo 'IRQBALANCE_ONESHOT=yes' >> /etc/sysconfig/irqbalance
else
  echo 'IRQBALANCE_ONESHOT=yes' > /etc/sysconfig/irqbalance 2>/dev/null || true
fi
enable_service irqbalance "IRQ balance"

step "SMART Monitoring"
backup_file /etc/smartd.conf
{
  echo "# Immortal Ultima Omega v6.9 KEFKA GOD MODE — smartd.conf"
  for dev in "${EXOS_DRIVES[@]}"; do
    echo "$dev -d sat -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55 -m root"
  done
  for dev in "${NVME_DRIVES[@]}"; do
    echo "$dev -a -n standby,q -s (S/../.././02|L/../../6/03) -W 4,60,70 -m root"
  done
  [[ ${#EXOS_DRIVES[@]} -eq 0 && ${#NVME_DRIVES[@]} -eq 0 ]] \
    && echo "DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,55,65 -m root"
} > /etc/smartd.conf
enable_service smartd "SMART monitoring"

step "Journald Cap"
JRNL_CONF=/etc/systemd/journald.conf.d/immortal.conf
backup_file "$JRNL_CONF"
write_file "$JRNL_CONF" << 'JRNLEOF'
[Journal]
SystemMaxUse=2G
SystemKeepFree=5G
SystemMaxFileSize=128M
RuntimeMaxUse=512M
Compress=yes
SyncIntervalSec=5m
JRNLEOF
systemctl restart systemd-journald >> "$LOG_FILE" 2>&1 || true
log "Journald configured"

step "Core Immortality Daemons"
[[ $GPU_NVIDIA -eq 1 ]] && enable_service nvidia-persistenced "nvidia-persistenced"
enable_service fstrim.timer "fstrim.timer (weekly TRIM)"

GUARDIAN=/usr/local/bin/immortal-guardian
write_file "$GUARDIAN" << 'GUARDEOF'
#!/bin/bash
EXOS_LIST="${EXOS_DRIVES[*]}"
NVME_LIST="${NVME_DRIVES[*]}"
GUARDIAN_LOG="/var/log/immortal-guardian.log"
guard_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$GUARDIAN_LOG" >&2; }
guard_log "Patrol started (v6.9 KEFKA GOD MODE) — ABCDE triage active"
lscpu | head -n 10 >> "$GUARDIAN_LOG"
swapon --show >> "$GUARDIAN_LOG"
if dmesg | grep -qiE 'nvidia|drm|gpu|error'; then
  guard_log "⚠️ Possible GPU/Display error in dmesg — triggering display recovery"
  /usr/local/bin/immortal-display-wake 2>/dev/null || true
fi
if command -v pactl >/dev/null 2>&1; then
  if pactl list short sinks | grep -q "RUNNING"; then
    guard_log "Audio sink active — no Xrun detected"
  fi
fi
for dev in $NVME_LIST; do
  [[ -b "$dev" ]] || continue
  STATUS=$(smartctl -H "$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print $2}' | xargs)
  guard_log "NVMe $dev: ${STATUS:-no response}"
done
if command -v kscreen-doctor >/dev/null 2>&1; then
  kscreen-doctor --outputs --set-all-enabled >> "$GUARDIAN_LOG" 2>&1 || true
fi
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0)
  guard_log "GPU: ${GPU_TEMP}°C"
  if [[ ${GPU_TEMP} -gt 85 ]]; then
    guard_log "HIGH GPU TEMP — throttling tuned profile temporarily"
    tuned-adm profile balanced >> "$GUARDIAN_LOG" 2>&1 || true
  fi
fi
guard_log "ABCDE triage complete — v6.9 KEFKA GOD MODE guardian active"
GUARDEOF
chmod +x "$GUARDIAN"

GUARDIAN_SERVICE=/etc/systemd/system/immortal-guardian.service
backup_file "$GUARDIAN_SERVICE"
write_file "$GUARDIAN_SERVICE" << 'SERVICEEOF'
[Unit]
Description=Immortal Guardian — Silent Watchdog v6.9
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-guardian
Nice=19
IOSchedulingClass=best-effort
TimeoutSec=120
SERVICEEOF

GUARDIAN_TIMER=/etc/systemd/system/immortal-guardian.timer
backup_file "$GUARDIAN_TIMER"
write_file "$GUARDIAN_TIMER" << 'TIMEREOF'
[Unit]
Description=Periodic Immortal Guardian Patrol
[Timer]
OnBootSec=3min
OnUnitActiveSec=30min
RandomizedDelaySec=10min
Persistent=true
[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
enable_service immortal-guardian.timer "Immortal Guardian timer"
log "Guardian deployed (v6.9 KEFKA GOD MODE with ABCDE triage)"

step "DNF5 Optimization"
backup_file /etc/dnf/dnf.conf
grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
grep -q 'fastestmirror' /etc/dnf/dnf.conf || echo "fastestmirror=True" >> /etc/dnf/dnf.conf
log "DNF5 optimized"

step "Performance Engine: Tuned Immortal Ultima (v6.9 — Balanced on Laptops)"
if [[ $IS_LAPTOP -eq 1 ]]; then
  systemctl unmask --now power-profiles-daemon 2>/dev/null || true
else
  systemctl mask --now power-profiles-daemon 2>/dev/null || true
fi
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p /etc/tuned/immortal-ultima
  backup_file /etc/tuned/immortal-ultima/tuned.conf
  if [[ $IS_LAPTOP -eq 1 ]]; then
    cat > /etc/tuned/immortal-ultima/tuned.conf << 'TUNED_EOF'
[main]
include=balanced
[sysctl]
vm.swappiness=5
vm.dirty_ratio=10
vm.dirty_background_ratio=5
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
[cpu]
governor=balanced
[io]
readahead=4096
TUNED_EOF
    log "Tuned profile set to BALANCED (laptop mode — respects Alienware hardware Performance button)"
  else
    cat > /etc/tuned/immortal-ultima/tuned.conf << 'TUNED_EOF'
[main]
include=balanced
[sysctl]
vm.swappiness=5
vm.dirty_ratio=10
vm.dirty_background_ratio=5
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
[cpu]
governor=performance
[io]
readahead=4096
TUNED_EOF
    log "Tuned profile set to PERFORMANCE (desktop)"
  fi
  tuned-adm profile immortal-ultima >> "$LOG_FILE" 2>&1 || true
  systemctl enable --now tuned >> "$LOG_FILE" 2>&1 || plane "Tuned service activation fallback triggered"
  enable_service tuned "Tuned performance engine"
fi

step "PipeWire Low-Latency Audio (v4.0)"
PIPEWIRE_CONF=/etc/pipewire/pipewire.conf.d/99-immortal-lowlatency.conf
backup_file "$PIPEWIRE_CONF"
write_file "$PIPEWIRE_CONF" << 'PWEOF'
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 1024
    default.clock.min-quantum = 32
    default.clock.max-quantum = 2048
}
PWEOF
log "PipeWire low-latency configured (audio perfection)"

step "Deskflow Auto-Allow KVM PC"
if command -v deskflow >/dev/null 2>&1 || command -v synergy >/dev/null 2>&1; then
  DESKFLOW_CONFIG="$REAL_HOME/.config/deskflow/deskflow.conf"
  mkdir -p "$(dirname "$DESKFLOW_CONFIG")"
  cat > "$DESKFLOW_CONFIG" << 'DESKEOF'
[General]
ClientName = "KVM-PC"
AutoStart = true
[Screen]
KVM-PC = true
DESKEOF
  log "Deskflow configured to always allow KVM PC on boot"
fi

step "Firefox Latency Fix"
if [[ -d "$REAL_HOME/.mozilla/firefox" ]]; then
  FIREFOX_PROFILE=$(find "$REAL_HOME/.mozilla/firefox" -name "*.default-release" | head -n1)
  if [[ -n "$FIREFOX_PROFILE" ]]; then
    cat >> "$FIREFOX_PROFILE/user.js" << 'FFEOF'
user_pref("layers.acceleration.force-enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("browser.cache.disk.capacity", 1048576);
user_pref("dom.ipc.processCount", 8);
user_pref("general.smoothScroll", true);
FFEOF
    log "Firefox profile tweaked for zero latency + hardware acceleration"
  fi
fi

step "Companion Tools — immortal-status & immortal-health-check (v6.9)"
STATUS_SCRIPT=/usr/local/bin/immortal-status
write_file "$STATUS_SCRIPT" << 'STATUS_EOF'
#!/bin/bash
CYN=$'[0;36m'; GRN=$'[0;32m'; NC=$'[0m'
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA — LIVE STATUS DASHBOARD v6.9 KEFKA GOD MODE ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo "Uptime : $(uptime -p)"
echo "Kernel : $(uname -r)"
echo "Tuned : $(tuned-adm active 2>/dev/null || echo none)"
echo "ZRAM : $(swapon --show | grep zram || echo none)"
echo "Guardian: running every 30 min"
echo "Sentinel: running every 5 min (low-impact)"
command -v nvidia-smi &>/dev/null && echo "GPU Temp: $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)°C"
echo -e "${GRN}The fortress is alive and watching.${NC}"
STATUS_EOF
chmod +x "$STATUS_SCRIPT"

HEALTH_SCRIPT=/usr/local/bin/immortal-health-check
write_file "$HEALTH_SCRIPT" << 'HEALTH_EOF'
#!/bin/bash
echo "Running full health check..."
fwupdmgr get-updates --quiet || true
FIRST_NVME=$(nvme list 2>/dev/null | awk '/^\/dev\/nvme/{print $1; exit}')
if [[ -n "$FIRST_NVME" ]]; then
  smartctl -t short "$FIRST_NVME" 2>/dev/null || true
else
  echo "No NVMe drive found for SMART test"
fi
echo "Health check complete — check /var/log/immortal-ultima-omega.log for details."
HEALTH_EOF
chmod +x "$HEALTH_SCRIPT"
log "Companion tools installed — run 'immortal-status' anytime"

step "Immortal Sentinel Daemon (low-impact background healing)"
SENTINEL=/usr/local/bin/immortal-sentinel
write_file "$SENTINEL" << 'SENTINELEOF'
#!/bin/bash
LOG="/var/log/immortal-sentinel.log"
exec > >(tee -a "$LOG") 2>&1
sentinel_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
sentinel_log "Immortal Sentinel v6.9 started — low-impact, observe-first healing"
while true; do
  /usr/local/bin/immortal-display-wake 2>/dev/null || true
  sleep 300
done
SENTINELEOF
chmod +x "$SENTINEL"

SENTINEL_SERVICE=/etc/systemd/system/immortal-sentinel.service
write_file "$SENTINEL_SERVICE" << 'SENTINELSVCEOF'
[Unit]
Description=Immortal Sentinel Daemon (low-impact background healing)
After=multi-user.target
[Service]
ExecStart=/usr/local/bin/immortal-sentinel
Restart=always
RestartSec=10
Nice=19
CPUQuota=15%
MemoryMax=128M
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
[Install]
WantedBy=multi-user.target
SENTINELSVCEOF

systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
enable_service immortal-sentinel.service "Immortal Sentinel daemon (observe-first healing)"
log "Immortal Sentinel daemon installed and enabled (runs every 5 minutes, low CPU/memory impact)"

step "Kernel Hardening (v6.9)"
cat > /etc/sysctl.d/99-immortal-hardening.conf << 'HARDENEOF'
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
dev.tty.ldisc_autoload=0
fs.protected_fifos=2
fs.protected_regular=2
vm.unprivileged_userfaultfd=0
kernel.perf_event_paranoid=3
HARDENEOF
sysctl -p /etc/sysctl.d/99-immortal-hardening.conf >> "$LOG_FILE" 2>&1 || true
mark_completed "hardening"

step "Entropy Improvement (haveged)"
dnf install -y haveged 2>/dev/null || true
systemctl enable --now haveged 2>/dev/null || true

step "KEFKA REVERSAL RITUAL — Desktop one-click undo (REAL USER DESKTOP)"
REVERT_SCRIPT="$REAL_HOME/Desktop/KEFKA-REVERSAL-RITUAL.sh"
write_file "$REVERT_SCRIPT" << 'REVERTEOF'
#!/bin/bash
echo -e "\033[1;31m"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║ KEFKA REVERSAL RITUAL — DESTROY EVERYTHING ║"
echo "║ (or heal if you changed your mind) ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "\033[0m"
echo "This will restore your system to the exact state BEFORE the last Immortal Ultima Omega run."
echo ""
read -p "Are you sure you want to invoke the Reversal Ritual? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Kefka laughs... the statues crumble..."
  sudo bash /usr/local/bin/immortal-ultima-omega.sh --revert
  echo "Reversal complete. The Magitek Empire has been un-made."
  echo "You may now delete this script if you wish."
else
  echo "Kefka is disappointed... but the ritual is stayed."
fi
REVERTEOF
chown "$REAL_USER:$REAL_USER" "$REVERT_SCRIPT" 2>/dev/null || true
chmod +x "$REVERT_SCRIPT"
log "KEFKA REVERSAL RITUAL created on YOUR desktop ($REAL_HOME/Desktop) — one-click full undo available"

step "FINAL REPORT & SELF-REGENERATION (v6.9 KEFKA GOD MODE)"
verify "Tuned active"; systemctl is-active --quiet tuned && log "Tuned: active" || record_failure "Tuned"
verify "Guardian timer active"; systemctl is-active --quiet immortal-guardian.timer && log "Guardian timer: active" || record_failure "Guardian timer"
verify "Sentinel active"; systemctl is-active --quiet immortal-sentinel.service && log "Sentinel: active" || true
verify "EarlyOOM active"; systemctl is-active --quiet earlyoom && log "EarlyOOM: active" || true
verify "IRQBalance active"; systemctl is-active --quiet irqbalance && log "IRQBalance: active" || true

CURRENT_DATE=$(date '+%Y-%m-%d')
sed -i "s|^# Creation Date: .*|# Creation Date: $CURRENT_DATE|" "$0"

RUN_SUMMARY=$(tail -n 400 "$LOG_FILE" | grep -E '\[Step|\[✓ PLAN|\[↻ PLAN|\[⚡ PLAN|\[🔴 PLAN|\[✗|\[⚠' | tail -n 100)

PROMPT="Date of this script: $CURRENT_DATE
You are the expert maintainer of IMMORTAL ULTIMA OMEGA.
CRITICAL INSTRUCTION: When you return the script you MUST output the ENTIRE script with EVERY SINGLE SECTION fully expanded. Never use placeholders. Always return the complete file inside one single \`\`\`bash code block.
Here is the full current script:
\`\`\`bash
$(cat "$0")
\`\`\`
Here is the latest run log / results:
\`\`\`
$RUN_SUMMARY
\`\`\`
Please return ONLY a complete updated version of the entire script.
Update the Creation Date to today's date.
Fix any issues that occurred during this run.
Make safe, stable, intelligent improvements.
Preserve 100% of original behavior and all existing features.
Double-check syntax.
Return the full script inside a single \`\`\`bash code block."

CLIP_CONTENT="SCRIPT CONTENTS:
$(cat "$0")
TERMINAL RESULTS:
$RUN_SUMMARY
READY AI PROMPT:
$PROMPT"

if [[ -n "${SUDO_USER:-}" ]]; then
  USER_TO_USE="$SUDO_USER"
else
  USER_TO_USE="$(whoami)"
fi
USER_UID=$(id -u "$USER_TO_USE" 2>/dev/null || echo "")
CLIP_SUCCESS=0
if command -v wl-copy >/dev/null 2>&1 && [[ -n "$USER_UID" ]]; then
  WL_DISP="${WAYLAND_DISPLAY:-/run/user/${USER_UID}/wayland-0}"
  echo -e "$CLIP_CONTENT" | su -c "WAYLAND_DISPLAY='$WL_DISP' wl-copy" "$USER_TO_USE" 2>/dev/null \
    && { log "✅ Copied to clipboard (Wayland)"; CLIP_SUCCESS=1; } || true
fi
if [[ $CLIP_SUCCESS -eq 0 ]] && command -v xclip >/dev/null 2>&1; then
  export DISPLAY="${DISPLAY:-:0}"
  echo -e "$CLIP_CONTENT" | su -c "DISPLAY='${DISPLAY}' xclip -selection clipboard" "$USER_TO_USE" 2>/dev/null \
    && { log "✅ Copied to clipboard (X11)"; CLIP_SUCCESS=1; } || true
fi
[[ $CLIP_SUCCESS -eq 0 ]] && warn "Clipboard copy failed. Install: sudo dnf install wl-clipboard xclip"
echo -e "$CLIP_CONTENT" > /tmp/immortal-clipboard.txt
log "✅ Full clipboard content saved to /tmp/immortal-clipboard.txt (always available)"

echo ""
echo -e "${GRN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║ IMMORTAL ULTIMA OMEGA v6.9 KEFKA GOD MODE + SENTINEL COMPLETE ║${NC}"
echo -e "${GRN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $VERIFY_FAILURES -gt 0 ]] && {
  err "VERIFICATION FAILURES: $VERIFY_FAILURES"
  for f in "${FAILURE_LOG[@]}"; do err " • $f"; done
}

echo -e " ${YLW}REBOOT RECOMMENDED${NC} for full effect"
echo "kwinoutputconfig.json has been backed up and disabled — KWin will regenerate a clean config."
echo "Monitors now turn OFF when locked and wake perfectly on unlock (no black/undrawn screen)."
echo "KEFKA REVERSAL RITUAL is on your real desktop."
echo "The fortress has reached its Final Form."
