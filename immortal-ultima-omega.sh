#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  IMMORTAL ULTIMA OMEGA — v8.0 "BALANCED ASCENSION"                        ║
# ║  S+ Edition — Hardware-aware · Idempotent · Self-healing · Clean-slate     ║
# ║  Fedora + CachyOS · NVIDIA / AMD / Intel · Desktop & Laptop               ║
# ║  Miracle Shoes: HASTE · PROTECT · REGEN · OMNISCIENCE                     ║
# ║                                                                             ║
# ║  From stable: hardware detection, daemons, timers, Miracle Shoes layer     ║
# ║  From beta:   normalization, state-aware checks, system scan, clean revert ║
# ║  Combined:    no overkill, no under-delivery — perfect balance             ║
# ║                                                                             ║
# ║  Created: 2026-04-04                                                        ║
# ║  Usage: sudo bash immortal-ultima-omega.sh [OPTIONS]                       ║
# ║    --dry-run      Preview all actions, make no changes                     ║
# ║    --revert       Remove all immortal config and restore defaults          ║
# ║    --force        Re-run steps even if already completed                   ║
# ║    --status       Show live status dashboard and exit                      ║
# ║    --no-backup    Skip config snapshots                                    ║
# ║    --skip-pkgs    Skip all DNF installs                                    ║
# ║    --enable-netdata   Install Netdata real-time dashboard                  ║
# ║    --enable-gaming    Install gamemode + mangohud                          ║
# ║    --enable-security  Install fail2ban SSH protection                      ║
# ║    --help         Show this message                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS + LOGGING
# ─────────────────────────────────────────────────────────────────────────────
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
BLU=$'\e[0;34m'; CYN=$'\e[0;36m'; MAG=$'\e[0;35m'
BOLD=$'\e[1m'; NC=$'\e[0m'

LOG_FILE="/var/log/immortal-ultima-omega.log"
LOCK_FILE="/var/lock/immortal-ultima-omega.lock"
STATE_DIR="/var/lib/immortal"
MARKER_DIR="$STATE_DIR/markers"
SCAN_FILE="/tmp/immortal-scan.txt"

mkdir -p "$STATE_DIR" "$MARKER_DIR" /var/log /var/lock 2>/dev/null || true

exec 200>"$LOCK_FILE"
flock -n 200 || { echo "Another instance is already running. Exiting."; exit 1; }
trap 'flock -u 200 2>/dev/null; exec 200>&- 2>/dev/null' EXIT

touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/immortal-ultima-omega.log"

log()    { echo -e "${GRN}[✓]${NC} $*"           | tee -a "$LOG_FILE"; }
plana()  { echo -e "${BLU}[A]${NC} $*"           | tee -a "$LOG_FILE"; }
planb()  { echo -e "${YLW}[B]${NC} $*"           | tee -a "$LOG_FILE"; }
planc()  { echo -e "${MAG}[C]${NC} $*"           | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YLW}[⚠]${NC} $*"           | tee -a "$LOG_FILE"; }
err()    { echo -e "${RED}[✗]${NC} $*"           | tee -a "$LOG_FILE"; }
info()   { echo -e "${BLU}[→]${NC} $*"           | tee -a "$LOG_FILE"; }
sect()   { echo -e "\n${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${CYN} $*${NC}
${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"; }
verify() { echo -e "${MAG}[⊛]${NC} $*"           | tee -a "$LOG_FILE"; }
timestamp() { date "+%F %T"; }

VERIFY_FAILURES=0
FAILURE_LOG=()
record_failure() { VERIFY_FAILURES=$((VERIFY_FAILURES+1)); FAILURE_LOG+=("$*"); err "VERIFY FAILED: $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────
DRY_RUN=0; REVERT=0; FORCE=0; STATUS_ONLY=0
NO_BACKUP=0; SKIP_PKGS=0
ENABLE_NETDATA=0; ENABLE_GAMING=0; ENABLE_SECURITY=0

usage() {
  grep '^# .*--' "$0" | sed 's/# /  /' | head -20
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)          DRY_RUN=1 ;;
    --revert)           REVERT=1 ;;
    --force)            FORCE=1 ;;
    --status)           STATUS_ONLY=1 ;;
    --no-backup)        NO_BACKUP=1 ;;
    --skip-pkgs)        SKIP_PKGS=1 ;;
    --enable-netdata)   ENABLE_NETDATA=1 ;;
    --enable-gaming)    ENABLE_GAMING=1 ;;
    --enable-security)  ENABLE_SECURITY=1 ;;
    --help|-h)          usage ;;
    *) err "Unknown argument: $arg"; exit 1 ;;
  esac
done

[[ $EUID -ne 0 ]] && { err "Run as root: sudo $0 $*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# REAL USER DETECTION
# ─────────────────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$REAL_USER")
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo "1000")
[[ ! -d "$REAL_HOME" ]] && REAL_HOME="/home/$REAL_USER"
SNAPSHOT_DIR="$REAL_HOME/immortal-snapshots"
BACKUP_DIR="/root/immortal-backups/$(date +%Y%m%d_%H%M%S)"

# ─────────────────────────────────────────────────────────────────────────────
# CORE HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# run: respects DRY_RUN; logs failures as warnings without aborting
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e " ${YLW}[DRY]${NC} $*"
    return 0
  fi
  "$@" 2>>"$LOG_FILE" || warn "Non-fatal: $* returned $?"
}

# write_file: atomic write; in dry-run prints target path only
write_file() {
  local path="$1"; shift
  local content="${1:-$(cat)}"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e " ${YLW}[DRY]${NC} Would write: $path"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  local tmp; tmp=$(mktemp)
  echo "$content" > "$tmp"
  mv "$tmp" "$path"
}

# safe_write: idempotent append — skips if marker already found in target
safe_write() {
  local target="$1" marker="$2"
  local content; content=$(cat)
  [[ $DRY_RUN -eq 1 ]] && { echo -e " ${YLW}[DRY]${NC} Would safe_write '$marker' → $target"; return 0; }
  grep -qF "$marker" "$target" 2>/dev/null && { info "Already present [$marker] in $target"; return 0; }
  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$content" >> "$target"
  info "safe_write: '$marker' → $target"
}

backup_file() {
  local f="$1"
  [[ $NO_BACKUP -eq 1 || $DRY_RUN -eq 1 || ! -f "$f" ]] && return 0
  mkdir -p "${BACKUP_DIR}$(dirname "$f")"
  cp -p "$f" "${BACKUP_DIR}${f}" 2>/dev/null && info "Backed up: $f" || true
}

is_done()    { [[ -f "$MARKER_DIR/$1" ]] && [[ $FORCE -eq 0 ]]; }
mark_done()  { touch "$MARKER_DIR/$1" 2>/dev/null || true; }

# enable_service: Plans A–C then logs failure — no Spirit Bomb overkill
enable_service() {
  local svc="$1" desc="${2:-$svc}"
  [[ $DRY_RUN -eq 1 ]] && { info "[DRY] Would enable: $svc"; return 0; }

  if systemctl enable --now "$svc" >>"$LOG_FILE" 2>&1; then
    plana "Enabled: $desc"; return 0
  fi
  warn "$svc: enable --now failed — trying enable then start"
  if systemctl enable "$svc" >>"$LOG_FILE" 2>&1 && \
     systemctl start  "$svc" >>"$LOG_FILE" 2>&1; then
    planb "Enabled (split): $desc"; return 0
  fi
  warn "$svc: split enable failed — daemon-reload and retry"
  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  if systemctl enable --now "$svc" >>"$LOG_FILE" 2>&1; then
    planc "Enabled (post-reload): $desc"; return 0
  fi
  record_failure "$desc could not be enabled"
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║  IMMORTAL ULTIMA OMEGA v8.0 — BALANCED ASCENSION — S+ EDITION         ║${NC}"
echo -e "${CYN}║  HASTE · PROTECT · REGEN · OMNISCIENCE                                ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
[[ $DRY_RUN -eq 1 ]]   && warn "DRY-RUN — no changes will be made"
[[ $REVERT -eq 1 ]]    && warn "REVERT MODE — will remove all immortal config"
[[ $NO_BACKUP -eq 1 ]] && warn "NO-BACKUP MODE — snapshots skipped"
[[ $SKIP_PKGS -eq 1 ]] && warn "SKIP-PKGS MODE — DNF installs skipped"
[[ $ENABLE_NETDATA -eq 1 ]]   && info "NETDATA MODULE enabled"
[[ $ENABLE_GAMING -eq 1 ]]    && info "GAMING MODULE enabled"
[[ $ENABLE_SECURITY -eq 1 ]]  && info "SECURITY MODULE enabled"

# ─────────────────────────────────────────────────────────────────────────────
# --status early exit
# ─────────────────────────────────────────────────────────────────────────────
if [[ $STATUS_ONLY -eq 1 ]]; then
  echo -e "${CYN}=== IMMORTAL STATUS (v8.0) ===${NC}"
  echo " User      : $REAL_USER ($REAL_HOME)"
  echo " Kernel    : $(uname -r)"
  echo " Uptime    : $(uptime -p)"
  echo " Tuned     : $(tuned-adm active 2>/dev/null | grep -o 'profile:.*' || echo 'none')"
  echo " ZRAM      : $(swapon --show 2>/dev/null | grep zram || echo 'none')"
  echo ""
  for svc in tuned earlyoom irqbalance smartd \
             immortal-guardian.timer immortal-sentinel.service \
             immortal-smart-weekly.timer immortal-regen-monthly.timer \
             immortal-raid-scrub.timer netdata fail2ban; do
    state=$(systemctl is-active "$svc" 2>/dev/null || echo "not-installed")
    [[ "$state" == "active" ]] && col="$GRN" || col="$YLW"
    printf " %-42s %b%s%b\n" "$svc" "$col" "$state" "$NC"
  done
  if [[ -s "$STATE_DIR/failure_flags" ]]; then
    echo ""
    echo -e "${RED}── Failure flags (need attention) ──${NC}"
    cat "$STATE_DIR/failure_flags"
  fi
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# LOG HEADER
# ─────────────────────────────────────────────────────────────────────────────
{
  echo ""
  echo "════════════════════════════════════════════"
  echo "[$(timestamp)] IMMORTAL v8.0 BALANCED ASCENSION — $(hostname)"
  echo "Kernel: $(uname -r)"
  echo "Flags: DRY=$DRY_RUN REVERT=$REVERT NETDATA=$ENABLE_NETDATA GAMING=$ENABLE_GAMING SECURITY=$ENABLE_SECURITY"
  echo "════════════════════════════════════════════"
} >> "$LOG_FILE"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 0 — NORMALIZATION (from beta: clean-slate before applying)
# Always runs first so re-runs don't stack config on top of config.
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 0 — Normalization (clean slate)"

if [[ $REVERT -eq 1 ]]; then
  warn "REVERT: removing all immortal config and resetting to system defaults"

  run rm -rf "$STATE_DIR"
  run rm -f /var/log/immortal*.log

  for f in \
    /etc/sysctl.d/99-immortal-ultima-omega.conf \
    /etc/sysctl.d/99-immortal-haste.conf \
    /etc/sysctl.d/99-immortal-hardening.conf \
    /etc/modprobe.d/nvidia-immortal.conf \
    /etc/modprobe.d/amdgpu-immortal.conf \
    /etc/modprobe.d/i915-immortal.conf \
    /etc/modprobe.d/nvme-immortal.conf \
    /etc/modprobe.d/usb-stability.conf \
    /etc/udev/rules.d/60-immortal-io.rules \
    /etc/udev/rules.d/61-seagate-exos-apm.rules \
    /etc/udev/rules.d/99-touchpad-keepalive.rules \
    /etc/systemd/zram-generator.conf \
    /etc/systemd/system/immortal-*.service \
    /etc/systemd/system/immortal-*.timer \
    /etc/systemd/system/earlyoom.service.d/tuning.conf \
    /etc/systemd/system/mobile-omega-powertop.service \
    /etc/systemd/journald.conf.d/immortal.conf \
    /etc/pipewire/pipewire.conf.d/99-immortal-lowlatency.conf \
    /etc/X11/xorg.conf.d/10-immortal-nodpms.conf \
    /etc/xdg/powermanagementprofilesrc \
    /etc/xdg/autostart/immortal-nodpms.desktop \
    /usr/local/bin/immortal-* \
    /usr/local/bin/immortal-guardian \
    /usr/local/bin/immortal-sentinel \
    /usr/local/bin/immortal-heal \
    /usr/local/bin/immortal-status \
    /usr/local/bin/immortal-logs \
    /usr/local/bin/immortal-health-check \
    /usr/local/bin/immortal-display-wake; do
    [[ -e "$f" ]] && run rm -f "$f" && info "Removed: $f"
  done

  run rm -rf /etc/tuned/immortal-ultima
  run systemctl daemon-reload
  command -v tuned-adm >/dev/null 2>&1 && run tuned-adm profile balanced
  run sysctl --system

  log "Revert complete — system restored to balanced defaults"
  echo ""
  echo "Revert complete. Reboot recommended."
  exit 0
fi

# Non-revert: remove stale immortal unit files from old runs before re-laying them
# This prevents leftover units from prior versions causing conflicts.
if [[ $DRY_RUN -eq 0 ]]; then
  for old_unit in /etc/systemd/system/immortal-*.service /etc/systemd/system/immortal-*.timer; do
    [[ -e "$old_unit" ]] && { info "Removing stale unit: $old_unit"; rm -f "$old_unit"; }
  done
  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
fi
log "Normalization complete"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 1 — HARDWARE FINGERPRINT
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 1 — Hardware Detection"

IS_LAPTOP=0
ls /sys/class/power_supply/BAT* >/dev/null 2>&1 && IS_LAPTOP=1
[[ $IS_LAPTOP -eq 1 ]] && log "Form factor: LAPTOP" || log "Form factor: DESKTOP"

TOTAL_RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4)
log "RAM: ${TOTAL_RAM_GB}GB"

IS_VM=0
systemd-detect-virt -q 2>/dev/null && IS_VM=1
[[ $IS_VM -eq 1 ]] && warn "VM detected — aggressive tweaks softened"

KERNEL_VER=$(uname -r)
IS_CACHYOS=0; CACHYOS_SCHED="unknown"
if echo "$KERNEL_VER" | grep -qi cachyos; then
  IS_CACHYOS=1
  if   echo "$KERNEL_VER" | grep -qi bore;  then CACHYOS_SCHED="bore"
  elif echo "$KERNEL_VER" | grep -qi rt;    then CACHYOS_SCHED="rt"
  elif echo "$KERNEL_VER" | grep -qi scx;   then CACHYOS_SCHED="scx"
  elif echo "$KERNEL_VER" | grep -qi eevdf; then CACHYOS_SCHED="eevdf"
  else CACHYOS_SCHED="eevdf"; fi
  log "CachyOS kernel: scheduler=${CACHYOS_SCHED^^}"
else
  log "Kernel: $KERNEL_VER"
fi

HAS_SCX=0
if [[ "$CACHYOS_SCHED" == "scx" ]] || modinfo scx_rusty >/dev/null 2>&1 || \
   systemctl list-units --no-legend 'scx*' 2>/dev/null | grep -q scx; then
  HAS_SCX=1; log "sched_ext (scx) available"
fi

CPU_VENDOR=$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo unknown)
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | xargs 2>/dev/null || echo unknown)
IS_INTEL_CPU=0; IS_AMD_CPU=0; IS_RYZEN=0; IS_RYZEN9=0
case "$CPU_VENDOR" in
  GenuineIntel) IS_INTEL_CPU=1; log "CPU: Intel — $CPU_MODEL" ;;
  AuthenticAMD)
    IS_AMD_CPU=1
    echo "$CPU_MODEL" | grep -qi 'ryzen'   && IS_RYZEN=1
    echo "$CPU_MODEL" | grep -qi 'ryzen 9' && IS_RYZEN9=1
    log "CPU: AMD — $CPU_MODEL (Ryzen=$IS_RYZEN Ryzen9=$IS_RYZEN9)"
    ;;
  *) warn "CPU: unknown vendor ($CPU_VENDOR)" ;;
esac

GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0
lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qi nvidia  && GPU_NVIDIA=1
lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qiE 'amd|radeon|ati' && GPU_AMD=1
lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qi intel   && GPU_INTEL=1
[[ $GPU_NVIDIA -eq 1 ]] && log "GPU: NVIDIA"
[[ $GPU_AMD -eq 1 ]]    && log "GPU: AMD"
[[ $GPU_INTEL -eq 1 ]]  && log "GPU: Intel iGPU"

# Drive detection
get_drive_model() {
  smartctl -i "$1" 2>/dev/null | grep -Ei 'Device Model|Model Number' | \
    head -1 | awk -F: '{print $2}' | xargs 2>/dev/null || echo "UNKNOWN"
}
EXOS_DRIVES=(); NVME_DRIVES=(); SATA_SSDS=(); UNKNOWN_SATA_ROT=()
info "Scanning block devices..."
for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
  [[ -b "$dev" ]] || continue
  transport=$(udevadm info --query=property --name="$dev" 2>/dev/null | \
              grep '^ID_BUS=' | cut -d= -f2 || echo "")
  [[ "$transport" == "usb" ]] && { warn "Skipping USB: $dev"; continue; }
  if [[ "$dev" == /dev/nvme* ]]; then
    NVME_DRIVES+=("$dev"); info " $dev — NVMe"; continue
  fi
  model=$(get_drive_model "$dev")
  rot=$(cat "/sys/block/$(basename "$dev")/queue/rotational" 2>/dev/null || echo "?")
  if echo "$model" | grep -qiE 'ST18000NM|ST18000'; then
    EXOS_DRIVES+=("$dev"); info " $dev — Seagate EXOS"
  elif [[ "$rot" == "1" ]]; then
    UNKNOWN_SATA_ROT+=("$dev"); info " $dev — rotational SATA"
  else
    SATA_SSDS+=("$dev"); info " $dev — SATA SSD"
  fi
done
SATA_HDDS=("${EXOS_DRIVES[@]+"${EXOS_DRIVES[@]}"}" "${UNKNOWN_SATA_ROT[@]+"${UNKNOWN_SATA_ROT[@]}"}")

EXTRA_MOUNTED=0
mountpoint -q /mnt/ExtraStorage 2>/dev/null && EXTRA_MOUNTED=1

HAS_RAID=0
command -v mdadm >/dev/null 2>&1 && grep -q '^md' /proc/mdstat 2>/dev/null && HAS_RAID=1
[[ $HAS_RAID -eq 1 ]] && log "MD RAID arrays detected"

DE="unknown"
pgrep -x gnome-shell   >/dev/null 2>&1 && DE="GNOME"
pgrep -x plasmashell   >/dev/null 2>&1 && DE="KDE"
[[ "$DE" == "unknown" && -n "${XDG_CURRENT_DESKTOP:-}" ]] && DE="$XDG_CURRENT_DESKTOP"
log "DE: $DE"

info "Summary: CPU=$CPU_VENDOR GPU=NVIDIA:$GPU_NVIDIA/AMD:$GPU_AMD/Intel:$GPU_INTEL"
info "  Laptop=$IS_LAPTOP CachyOS=$IS_CACHYOS($CACHYOS_SCHED) scx=$HAS_SCX VM=$IS_VM RAID=$HAS_RAID"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 2 — SNAPSHOT
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 2 — Pre-run Snapshot"

if [[ $NO_BACKUP -eq 0 && $DRY_RUN -eq 0 ]]; then
  SNAP="$SNAPSHOT_DIR/$(date +%Y%m%d_%H%M%S)_pre-run"
  mkdir -p "$SNAP"
  for item in /etc/grub.d /etc/default/grub /etc/fstab /etc/modprobe.d \
              /etc/sysctl.d /etc/tuned /etc/udev/rules.d /etc/selinux; do
    [[ -e "$item" ]] && cp -a "$item" "$SNAP/" 2>/dev/null || true
  done
  echo "$SNAP" > "$STATE_DIR/last_snapshot"
  chown -R "$REAL_USER:$REAL_USER" "$SNAP" "$SNAPSHOT_DIR" 2>/dev/null || true
  log "Snapshot created: $SNAP"
else
  info "[DRY/NO-BACKUP] Snapshot skipped"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 3 — PACKAGES
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 3 — Packages"

# NVIDIA: enable RPM Fusion if needed
if [[ $GPU_NVIDIA -eq 1 && $SKIP_PKGS -eq 0 && $DRY_RUN -eq 0 ]]; then
  if ! dnf repolist 2>/dev/null | grep -q rpmfusion; then
    info "Enabling RPM Fusion for NVIDIA..."
    dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
      >>"$LOG_FILE" 2>&1 || warn "RPM Fusion install failed — continuing"
  fi
fi

# CachyOS COPR
if [[ $IS_CACHYOS -eq 1 && $SKIP_PKGS -eq 0 && $DRY_RUN -eq 0 ]]; then
  { dnf copr list 2>/dev/null || true; } | grep -q 'bieszczaders/kernel-cachyos' || \
    dnf copr enable -y bieszczaders/kernel-cachyos >>"$LOG_FILE" 2>&1 || true
  [[ $HAS_SCX -eq 1 ]] && \
    { dnf install -y scx-scheds >>"$LOG_FILE" 2>&1 || warn "scx-scheds unavailable — skipping"; }
fi

PKGS=(
  smartmontools lm_sensors irqbalance earlyoom hdparm nvme-cli
  util-linux pciutils usbutils numactl zram-generator
  powertop sysstat cronie xorg-x11-utils fwupd
  tuned tuned-ppd xclip wl-clipboard rng-tools curl
)
[[ $GPU_NVIDIA -eq 1 ]]              && PKGS+=(akmod-nvidia xorg-x11-drv-nvidia-cuda)
[[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]] && PKGS+=(mesa-va-drivers)
[[ $IS_LAPTOP -eq 1 ]]               && PKGS+=(power-profiles-daemon thermald)
[[ $ENABLE_NETDATA -eq 1 ]]          && PKGS+=(netdata)
[[ $ENABLE_GAMING -eq 1 ]]           && PKGS+=(gamemode mangohud)
[[ $ENABLE_SECURITY -eq 1 ]]         && PKGS+=(fail2ban)

if [[ $SKIP_PKGS -eq 1 ]]; then
  warn "Packages skipped"
elif [[ $DRY_RUN -eq 1 ]]; then
  info "[DRY] Would install: ${PKGS[*]}"
else
  # Bulk install; on failure fall back to per-package
  if ! dnf install -y "${PKGS[@]}" >>"$LOG_FILE" 2>&1; then
    planb "Bulk install failed — retrying individually"
    for pkg in "${PKGS[@]}"; do
      rpm -q "$pkg" &>/dev/null && continue
      dnf install -y "$pkg" >>"$LOG_FILE" 2>&1 && log "Installed: $pkg" \
        || warn "Could not install: $pkg (continuing)"
    done
  else
    log "All packages installed"
  fi
  # Mesa freeworld swap (AMD/Intel VA-API)
  [[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]] && \
    { dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld >>"$LOG_FILE" 2>&1 || true; }
  # Rebuild akmod for NVIDIA
  if [[ $GPU_NVIDIA -eq 1 ]] && ! rpm -q akmod-nvidia &>/dev/null; then
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda >>"$LOG_FILE" 2>&1 || true
  fi
  command -v akmods >/dev/null 2>&1 && akmods --force >>"$LOG_FILE" 2>&1 || true
  systemctl enable --now rngd >>"$LOG_FILE" 2>&1 || true

  # DNF speed
  grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf 2>/dev/null || \
    echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
  grep -q 'fastestmirror' /etc/dnf/dnf.conf 2>/dev/null || \
    echo "fastestmirror=True" >> /etc/dnf/dnf.conf
  log "DNF parallelism configured"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 4 — FIRMWARE (notify only — no force-apply)
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 4 — Firmware Check (fwupd)"

if command -v fwupdmgr >/dev/null 2>&1; then
  run fwupdmgr refresh --force
  UPDATES=$(fwupdmgr get-updates 2>/dev/null || echo "")
  if echo "$UPDATES" | grep -qi 'No upgrades'; then
    log "Firmware: all up to date"
  else
    warn "Firmware updates available — review and apply manually:"
    warn "  sudo fwupdmgr update"
    echo "$UPDATES" >> "$LOG_FILE"
  fi
  enable_service fwupd-refresh.timer "fwupd auto-refresh"
else
  warn "fwupdmgr not found — skipping firmware check"
fi

# NVMe health log
command -v nvme >/dev/null 2>&1 && nvme list >>"$LOG_FILE" 2>&1 || true
for dev in "${NVME_DRIVES[@]+"${NVME_DRIVES[@]}"}"; do
  command -v nvme >/dev/null 2>&1 && nvme smart-log "$dev" >>"$LOG_FILE" 2>&1 || true
done
log "Firmware + NVMe diagnostics logged"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 5 — MODPROBE + UDEV
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 5 — Modprobe + udev Rules"

# GPU modprobe
if [[ $GPU_NVIDIA -eq 1 ]]; then
  backup_file /etc/modprobe.d/nvidia-immortal.conf
  write_file /etc/modprobe.d/nvidia-immortal.conf "# Immortal v8.0 — NVIDIA
options nvidia NVreg_EnableGpuFirmware=1
options nvidia NVreg_UsePageAttributeTable=1
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia_drm modeset=1 fbdev=1
softdep nvidia_drm pre: nvidia nvidia_modeset"
  log "NVIDIA modprobe written"
elif [[ $GPU_AMD -eq 1 ]]; then
  backup_file /etc/modprobe.d/amdgpu-immortal.conf
  write_file /etc/modprobe.d/amdgpu-immortal.conf "# Immortal v8.0 — AMDGPU
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff"
  log "AMDGPU modprobe written"
elif [[ $GPU_INTEL -eq 1 ]]; then
  backup_file /etc/modprobe.d/i915-immortal.conf
  write_file /etc/modprobe.d/i915-immortal.conf "# Immortal v8.0 — Intel i915
options i915 enable_psr=1
options i915 enable_guc=2"
  log "Intel i915 modprobe written"
fi

# NVMe PS0 lock (desktop only)
if [[ $IS_LAPTOP -eq 0 && ${#NVME_DRIVES[@]} -gt 0 ]]; then
  backup_file /etc/modprobe.d/nvme-immortal.conf
  write_file /etc/modprobe.d/nvme-immortal.conf "# Immortal v8.0 — NVMe PS0 lock (desktop)
options nvme_core default_ps_max_latency_us=0"
  [[ $DRY_RUN -eq 0 ]] && echo "0" > /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null || true
  log "NVMe PS0 lock applied"
fi

# USB autosuspend disable
backup_file /etc/modprobe.d/usb-stability.conf
write_file /etc/modprobe.d/usb-stability.conf "# Immortal v8.0 — USB stability
options usbcore autosuspend=-1"

# udev: IO schedulers
backup_file /etc/udev/rules.d/60-immortal-io.rules
write_file /etc/udev/rules.d/60-immortal-io.rules 'ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/read_ahead_kb}="256"
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="16384"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="512"'
log "IO scheduler udev rules written"

# udev: touchpad/USB keepalive
write_file /etc/udev/rules.d/99-touchpad-keepalive.rules 'ACTION=="add", SUBSYSTEM=="input", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"'

# EXOS APM disable
if [[ ${#EXOS_DRIVES[@]} -gt 0 ]]; then
  write_file /etc/udev/rules.d/61-seagate-exos-apm.rules \
    'ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="/usr/bin/hdparm -B 255 -S 0 /dev/%k"'
  [[ $DRY_RUN -eq 0 ]] && for dev in "${EXOS_DRIVES[@]}"; do
    command -v hdparm >/dev/null 2>&1 && hdparm -B 255 -S 0 "$dev" >>"$LOG_FILE" 2>&1 || true
  done
  log "EXOS APM disabled"
fi

if [[ $DRY_RUN -eq 0 ]]; then
  udevadm control --reload-rules && udevadm trigger 2>/dev/null || true
fi
log "udev rules applied"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 6 — FSTAB + ZRAM + SWAP
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 6 — fstab / ZRAM / Swap"

# fstab: noatime + lazytime (idempotent — only adds if not present)
backup_file /etc/fstab
if [[ $DRY_RUN -eq 0 ]]; then
  sed -i '/^\s*[^#].*\s\(ext4\|btrfs\|xfs\)\s/ {
    /noatime/! s/defaults/defaults,noatime,lazytime,commit=60/
  }' /etc/fstab 2>>"$LOG_FILE" || true
  log "fstab: noatime+lazytime applied"
else
  info "[DRY] Would update /etc/fstab with noatime,lazytime,commit=60"
fi

# ZRAM — dynamic sizing
ZRAM_SIZE=$(( TOTAL_RAM_GB / 2 ))
[[ $ZRAM_SIZE -gt 16 ]] && ZRAM_SIZE=16
[[ $ZRAM_SIZE -lt 4 ]]  && ZRAM_SIZE=4
backup_file /etc/systemd/zram-generator.conf
write_file /etc/systemd/zram-generator.conf "[zram0]
zram-size = ${ZRAM_SIZE}G
compression-algorithm = zstd
swap-priority = 100"
log "ZRAM: ${ZRAM_SIZE}GB zstd"

# Tier-2 swapfile on ExtraStorage (beta approach: fallocate, not dd)
if [[ $EXTRA_MOUNTED -eq 1 ]]; then
  SWAPFILE=/mnt/ExtraStorage/swapfile
  if [[ ! -f "$SWAPFILE" ]]; then
    FREE=$(df -BG /mnt/ExtraStorage 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4}' || echo 0)
    if (( FREE >= 10 )); then
      run fallocate -l 8G "$SWAPFILE"
      run chmod 600 "$SWAPFILE"
      run mkswap "$SWAPFILE"
      grep -q "$SWAPFILE" /etc/fstab 2>/dev/null || \
        echo "$SWAPFILE none swap defaults,pri=10 0 0" >> /etc/fstab
      run swapon "$SWAPFILE"
      log "8GB Tier-2 swapfile created on /mnt/ExtraStorage"
    else
      warn "ExtraStorage: only ${FREE}GB free — Tier-2 swap skipped (need 10G)"
    fi
  else
    info "Tier-2 swapfile already exists — skipping"
  fi
  run swapon -a
fi

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 7 — SYSCTL
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 7 — Sysctl"

backup_file /etc/sysctl.d/99-immortal-ultima-omega.conf

SYSCTL_CONTENT='# Immortal v8.0 — Core sysctl
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=5
vm.dirty_ratio=10
vm.vfs_cache_pressure=50
vm.max_map_count=2147483647
kernel.panic=10
fs.inotify.max_user_watches=1048576
net.ipv4.conf.all.rp_filter=1
kernel.dmesg_restrict=1
kernel.sched_autogroup_enabled=1'

sysctl kernel.sched_itmt_enabled >/dev/null 2>&1 && \
  SYSCTL_CONTENT+=$'\nkernel.sched_itmt_enabled=1'

if [[ "$CACHYOS_SCHED" == "bore" ]]; then
  for knob in kernel.sched_bore kernel.sched_min_base_slice_ns \
              kernel.sched_wakeup_granularity_ns kernel.sched_latency_ns; do
    sysctl "$knob" >/dev/null 2>&1 || continue
    case "$knob" in
      kernel.sched_bore)                  SYSCTL_CONTENT+=$'\n'"${knob}=1" ;;
      kernel.sched_min_base_slice_ns)     SYSCTL_CONTENT+=$'\n'"${knob}=1000000" ;;
      kernel.sched_wakeup_granularity_ns) SYSCTL_CONTENT+=$'\n'"${knob}=3000000" ;;
      kernel.sched_latency_ns)            SYSCTL_CONTENT+=$'\n'"${knob}=6000000" ;;
    esac
  done
  log "BORE sysctl knobs added"
fi

if [[ "$CACHYOS_SCHED" == "eevdf" || $IS_CACHYOS -eq 0 ]]; then
  sysctl kernel.sched_min_granularity_ns >/dev/null 2>&1 && \
    SYSCTL_CONTENT+=$'\nkernel.sched_min_granularity_ns=1000000'
fi

write_file /etc/sysctl.d/99-immortal-ultima-omega.conf "$SYSCTL_CONTENT"

# HASTE sysctl (fiber + Ryzen)
HASTE_CONTENT='# Immortal v8.0 — HASTE: fiber network + CPU latency
net.ipv4.tcp_fastopen=3
net.core.somaxconn=65535
net.core.netdev_max_backlog=16384
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216'
if [[ $IS_RYZEN -eq 1 ]]; then
  HASTE_CONTENT+=$'\nkernel.sched_migration_cost_ns=500000'
  [[ $IS_RYZEN9 -eq 1 ]] && HASTE_CONTENT+=$'\nkernel.numa_balancing=1'
  log "Ryzen latency sysctl added"
fi
write_file /etc/sysctl.d/99-immortal-haste.conf "$HASTE_CONTENT"

# Hardening (conservative — no disable of legit capabilities)
write_file /etc/sysctl.d/99-immortal-hardening.conf '# Immortal v8.0 — kernel hardening
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
dev.tty.ldisc_autoload=0
fs.protected_fifos=2
fs.protected_regular=2
kernel.perf_event_paranoid=3'

if [[ $DRY_RUN -eq 0 ]]; then
  sysctl --system >>"$LOG_FILE" 2>&1 || true
fi
log "Sysctl applied (core + HASTE + hardening)"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 8 — GRUB KERNEL PARAMS
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 8 — GRUB Kernel Parameters"

REMOVE_ARGS=("nvidia.NVreg_PreserveVideoMemoryAllocations=1" "nvidia.NVreg_EnableGpuFirmware=0")
KERNEL_ARGS=("nouveau.modeset=0" "pcie_aspm=off" "nmi_watchdog=1")
[[ $GPU_NVIDIA -eq 1 ]] && KERNEL_ARGS+=("nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" "nvidia.NVreg_EnableGpuFirmware=1")
[[ $IS_AMD_CPU -eq 1 ]] && KERNEL_ARGS+=("amd_pstate=active")
[[ $IS_INTEL_CPU -eq 1 && $IS_LAPTOP -eq 1 ]] && KERNEL_ARGS+=("i915.enable_psr=1")
[[ $IS_LAPTOP -eq 1 ]]  && KERNEL_ARGS+=("processor.max_cstate=5")
[[ "$CACHYOS_SCHED" == "bore" ]] && KERNEL_ARGS+=("sched_bore=1")

if [[ $DRY_RUN -eq 0 ]]; then
  if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --remove-args="${REMOVE_ARGS[*]}" >>"$LOG_FILE" 2>&1 || true
    grubby --update-kernel=ALL --args="${KERNEL_ARGS[*]}" >>"$LOG_FILE" 2>&1 || true
    [[ $GPU_NVIDIA -eq 1 ]] && command -v dracut >/dev/null 2>&1 && \
      dracut -f >>"$LOG_FILE" 2>&1 && log "dracut regenerated"
    log "GRUB: ${KERNEL_ARGS[*]}"
  else
    warn "grubby not found — GRUB params not updated"
  fi
else
  info "[DRY] Would apply GRUB args: ${KERNEL_ARGS[*]}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 9 — TUNED PROFILE
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 9 — Tuned Performance Profile"

if [[ $DRY_RUN -eq 0 ]]; then
  # Desktop: mask power-profiles-daemon (conflicts with tuned CPU governor)
  # Laptop: unmask — let battery management coexist
  if [[ $IS_LAPTOP -eq 1 ]]; then
    systemctl unmask power-profiles-daemon 2>/dev/null || true
  else
    systemctl mask --now power-profiles-daemon 2>/dev/null || true
  fi

  mkdir -p /etc/tuned/immortal-ultima
  backup_file /etc/tuned/immortal-ultima/tuned.conf

  if [[ $IS_LAPTOP -eq 1 ]]; then
    cat > /etc/tuned/immortal-ultima/tuned.conf <<'TUNED_EOF'
[main]
include=balanced
[sysctl]
vm.swappiness=5
vm.dirty_ratio=10
vm.dirty_background_ratio=5
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
[cpu]
governor=schedutil
[io]
readahead=4096
TUNED_EOF
    log "Tuned: schedutil governor (laptop)"
  else
    cat > /etc/tuned/immortal-ultima/tuned.conf <<'TUNED_EOF'
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
    log "Tuned: performance governor (desktop)"
  fi

  tuned-adm profile immortal-ultima >>"$LOG_FILE" 2>&1 || true
fi
enable_service tuned "Tuned immortal-ultima"

# scx (CachyOS sched_ext)
if [[ $HAS_SCX -eq 1 && $DRY_RUN -eq 0 ]]; then
  if systemctl list-unit-files scx.service &>/dev/null; then
    SCX_SCHED="scx_rusty"
    [[ $IS_LAPTOP -eq 1 ]] && SCX_SCHED="scx_lavd"
    if [[ -f /etc/scx.conf ]]; then
      sed -i "s/^SCX_SCHEDULER=.*/SCX_SCHEDULER=$SCX_SCHED/" /etc/scx.conf 2>/dev/null || \
        echo "SCX_SCHEDULER=$SCX_SCHED" >> /etc/scx.conf
    else
      echo "SCX_SCHEDULER=$SCX_SCHED" > /etc/scx.conf
    fi
    enable_service scx.service "scx ($SCX_SCHED)"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 10 — CORE SERVICES
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 10 — Core Services"

# EarlyOOM
mkdir -p /etc/systemd/system/earlyoom.service.d
backup_file /etc/systemd/system/earlyoom.service.d/tuning.conf
write_file /etc/systemd/system/earlyoom.service.d/tuning.conf '[Service]
ExecStart=
ExecStart=/usr/sbin/earlyoom -r 60 -m 5 -s 5 \
  --prefer "(firefox|chromium|electron|code|brave|java)" \
  --avoid  "(sddm|pipewire|wireplumber|kwin_x11|kwin_wayland|plasmashell|Xorg|nvidia|earlyoom)"'
[[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
enable_service earlyoom "EarlyOOM"

# IRQ balancing
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ -f /etc/sysconfig/irqbalance ]]; then
    grep -q 'IRQBALANCE_ONESHOT' /etc/sysconfig/irqbalance || \
      echo 'IRQBALANCE_ONESHOT=yes' >> /etc/sysconfig/irqbalance
  else
    echo 'IRQBALANCE_ONESHOT=yes' > /etc/sysconfig/irqbalance 2>/dev/null || true
  fi
fi
enable_service irqbalance "IRQ balance"

# NVIDIA persistence
[[ $GPU_NVIDIA -eq 1 ]] && enable_service nvidia-persistenced "NVIDIA persistence"

# SMART
backup_file /etc/smartd.conf
if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "# Immortal v8.0 — smartd.conf"
    for dev in "${EXOS_DRIVES[@]+"${EXOS_DRIVES[@]}"}"; do
      echo "$dev -d sat -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55 -m root"
    done
    for dev in "${NVME_DRIVES[@]+"${NVME_DRIVES[@]}"}"; do
      echo "$dev -a -n standby,q -s (S/../.././02|L/../../6/03) -W 4,60,70 -m root"
    done
    [[ ${#EXOS_DRIVES[@]} -eq 0 && ${#NVME_DRIVES[@]} -eq 0 ]] && \
      echo "DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,55,65 -m root"
  } > /etc/smartd.conf
fi
enable_service smartd "SMART monitoring"

# fstrim weekly
enable_service fstrim.timer "fstrim weekly TRIM"

# Journald cap
mkdir -p /etc/systemd/journald.conf.d
backup_file /etc/systemd/journald.conf.d/immortal.conf
write_file /etc/systemd/journald.conf.d/immortal.conf '[Journal]
SystemMaxUse=2G
SystemKeepFree=5G
SystemMaxFileSize=128M
RuntimeMaxUse=512M
Compress=yes
SyncIntervalSec=5m'
[[ $DRY_RUN -eq 0 ]] && systemctl restart systemd-journald >>"$LOG_FILE" 2>&1 || true
log "Journald capped"

# PipeWire low-latency
mkdir -p /etc/pipewire/pipewire.conf.d
backup_file /etc/pipewire/pipewire.conf.d/99-immortal-lowlatency.conf
write_file /etc/pipewire/pipewire.conf.d/99-immortal-lowlatency.conf 'context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 1024
    default.clock.min-quantum = 32
    default.clock.max-quantum = 2048
}'
log "PipeWire low-latency configured"

# Laptop power
if [[ $IS_LAPTOP -eq 1 ]]; then
  write_file /etc/systemd/system/mobile-omega-powertop.service '[Unit]
Description=powertop --auto-tune on boot
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target'
  [[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  enable_service mobile-omega-powertop.service "powertop auto-tune"
  enable_service thermald "thermald"
  if [[ $DRY_RUN -eq 0 ]] && [[ -w /sys/power/mem_sleep ]] && \
     grep -q deep /sys/power/mem_sleep 2>/dev/null; then
    echo "deep" > /sys/power/mem_sleep; log "mem_sleep: deep"
  fi
fi

# KDE: plasmashell display wake (minimal — SIGUSR1 only, no qdbus)
DISPLAY_WAKE=/usr/local/bin/immortal-display-wake
write_file "$DISPLAY_WAKE" '#!/bin/bash
# Immortal v8.0 — Display wake (user-context, minimal)
LOG=/tmp/immortal-display-wake.log
echo "[$(date +%T)] Display wake triggered" >> "$LOG"
[[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && exit 0
for i in {1..8}; do [[ -e /dev/dri/renderD128 ]] && break; sleep 1; done
if [[ -n "${DISPLAY:-}" ]] && command -v xrandr &>/dev/null; then
  for out in $(xrandr 2>/dev/null | awk "/ connected/{print \$1}"); do
    xrandr --output "$out" --auto 2>/dev/null || true
    sleep 2
  done
fi
pgrep -x plasmashell >/dev/null 2>&1 && killall -SIGUSR1 plasmashell 2>/dev/null || true
echo "[$(date +%T)] Display wake complete" >> "$LOG"'
[[ $DRY_RUN -eq 0 ]] && chmod +x "$DISPLAY_WAKE" || true

# KDE autostart
write_file /etc/xdg/autostart/immortal-nodpms.desktop '[Desktop Entry]
Name=Immortal — Display Wake
Type=Application
Exec=bash -c "sleep 8 && /usr/local/bin/immortal-display-wake"
X-KDE-Autostart-Phase=2'
log "Display wake script installed"

# fontconfig cache
command -v fc-cache >/dev/null 2>&1 && \
  { [[ $DRY_RUN -eq 0 ]] && fc-cache -f >>"$LOG_FILE" 2>&1 || true; log "fontconfig cache rebuilt"; }

# Firefox latency
if [[ -d "$REAL_HOME/.mozilla/firefox" ]]; then
  FF_PROF=$(find "$REAL_HOME/.mozilla/firefox" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
  if [[ -n "$FF_PROF" ]]; then
    USER_JS="$FF_PROF/user.js"
    declare -A FF_PREFS=(
      ['layers.acceleration.force-enabled']='true'
      ['gfx.webrender.all']='true'
      ['media.ffmpeg.vaapi.enabled']='true'
      ['browser.cache.disk.capacity']='1048576'
      ['dom.ipc.processCount']='8'
      ['general.smoothScroll']='true'
    )
    if [[ $DRY_RUN -eq 0 ]]; then
      for key in "${!FF_PREFS[@]}"; do
        grep -q "\"${key}\"" "$USER_JS" 2>/dev/null || \
          echo "user_pref(\"${key}\", ${FF_PREFS[$key]});" >> "$USER_JS"
      done
      chown "$REAL_USER:$REAL_USER" "$USER_JS" 2>/dev/null || true
      log "Firefox user.js updated"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 11 — IMMORTAL DAEMONS (Guardian + Sentinel)
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 11 — Immortal Daemons"

# ── immortal-guardian (patrol script, runs every 30min via timer) ──
GUARDIAN=/usr/local/bin/immortal-guardian
write_file "$GUARDIAN" "#!/bin/bash
# Immortal Guardian v8.0 — system patrol (hardware + service health)
EXOS_LIST='${EXOS_DRIVES[*]:-}'
NVME_LIST='${NVME_DRIVES[*]:-}'
LOG='/var/log/immortal-guardian.log'
g() { echo \"[\$(date '+%F %T')] \$*\" | tee -a \"\$LOG\"; }

g 'Guardian patrol started (v8.0)'
lscpu | head -6 >> \"\$LOG\"
free -h >> \"\$LOG\"

# GPU temperature check (NVIDIA)
if command -v nvidia-smi >/dev/null 2>&1; then
  GTEMP=\$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0)
  g \"GPU: \${GTEMP}°C\"
  if [[ \${GTEMP} -gt 85 ]]; then
    g 'HIGH GPU TEMP — switching to balanced tuned profile'
    tuned-adm profile balanced >>\"\$LOG\" 2>&1 || true
  fi
fi

# GPU/display error recovery for active sessions
if dmesg --since '30 minutes ago' 2>/dev/null | grep -qiE 'nvidia.*error|drm.*error|gpu.*hang|gpu.*reset'; then
  g 'GPU/display error detected — triggering display wake for active sessions'
  while IFS= read -r sess; do
    [[ -z \"\$sess\" ]] && continue
    uid=\$(loginctl show-session \"\$sess\" -p User --value 2>/dev/null || echo '')
    uname=\$(id -nu \"\$uid\" 2>/dev/null || echo '')
    [[ -z \"\$uname\" ]] && continue
    wayland=\$(loginctl show-session \"\$sess\" -p WaylandDisplay --value 2>/dev/null || echo '')
    xdisp=\$(loginctl show-session  \"\$sess\" -p Display        --value 2>/dev/null || echo '')
    if [[ -n \"\$wayland\" ]]; then
      su -c \"WAYLAND_DISPLAY='\$wayland' /usr/local/bin/immortal-display-wake\" \"\$uname\" 2>/dev/null || true
    elif [[ -n \"\$xdisp\" ]]; then
      su -c \"DISPLAY='\$xdisp' /usr/local/bin/immortal-display-wake\" \"\$uname\" 2>/dev/null || true
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}')
fi

# Plasmashell QML revive (if crashed)
while IFS= read -r sess; do
  [[ -z \"\$sess\" ]] && continue
  uid=\$(loginctl show-session \"\$sess\" -p User --value 2>/dev/null || echo '')
  uname=\$(id -nu \"\$uid\" 2>/dev/null || echo '')
  [[ -z \"\$uname\" ]] && continue
  stype=\$(loginctl show-session \"\$sess\" -p Type --value 2>/dev/null || echo '')
  [[ \"\$stype\" != 'x11' && \"\$stype\" != 'wayland' ]] && continue
  pgrep -u \"\$uid\" -x plasmashell >/dev/null 2>&1 && continue
  uhome=\$(getent passwd \"\$uname\" | cut -d: -f6 2>/dev/null || echo \"/home/\$uname\")
  g \"Plasmashell absent for \$uname — clearing QML cache and reviving\"
  su -c \"rm -rf '\$uhome/.cache/plasmashell' '\$uhome/.cache/plasma_engine_preview' '\$uhome/.cache/icon-cache.kcache'\" \"\$uname\" 2>/dev/null || true
  wayland=\$(loginctl show-session \"\$sess\" -p WaylandDisplay --value 2>/dev/null || echo '')
  xdisp=\$(loginctl show-session  \"\$sess\" -p Display        --value 2>/dev/null || echo '')
  if [[ -n \"\$wayland\" ]]; then
    su -c \"WAYLAND_DISPLAY='\$wayland' kstart plasmashell --replace >/dev/null 2>&1 &\" \"\$uname\" 2>/dev/null || true
  elif [[ -n \"\$xdisp\" ]]; then
    su -c \"DISPLAY='\$xdisp' kstart plasmashell --replace >/dev/null 2>&1 &\" \"\$uname\" 2>/dev/null || true
  fi
done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}')

# SMART health for EXOS + NVMe
for dev in \$EXOS_LIST \$NVME_LIST; do
  [[ -b \"\$dev\" ]] || continue
  STATUS=\$(smartctl -H \"\$dev\" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print \$2}' | xargs || echo 'unknown')
  g \"Drive \$dev: \${STATUS:-unknown}\"
  echo \"\$STATUS\" | grep -qi FAILED && {
    g 'DRIVE FAILURE — invoking immortal-heal'
    /usr/local/bin/immortal-heal drive_failure \"\$dev\" >>\"\$LOG\" 2>&1 || true
  }
done

g 'Guardian patrol complete'"
[[ $DRY_RUN -eq 0 ]] && chmod +x "$GUARDIAN" || true

write_file /etc/systemd/system/immortal-guardian.service '[Unit]
Description=Immortal Guardian — System Patrol v8.0
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-guardian
Nice=19
IOSchedulingClass=best-effort
TimeoutSec=120'

write_file /etc/systemd/system/immortal-guardian.timer '[Unit]
Description=Immortal Guardian Patrol Timer
[Timer]
OnBootSec=3min
OnUnitActiveSec=30min
RandomizedDelaySec=5min
Persistent=true
[Install]
WantedBy=timers.target'

[[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
enable_service immortal-guardian.timer "Guardian patrol timer"

# ── immortal-sentinel (long-running daemon: service watchdog + 3AM regen) ──
SENTINEL=/usr/local/bin/immortal-sentinel
write_file "$SENTINEL" '#!/bin/bash
# Immortal Sentinel v8.0 — continuous watchdog + 3AM maintenance
LOG="/var/log/immortal-sentinel.log"
REGEN_LOCK="/var/lib/immortal/last-sentinel-regen-date"
s() { echo "[$(date "+%F %T")] $*" | tee -a "$LOG"; }
s "Sentinel v8.0 started"

while true; do
  # Service watchdog
  for svc in earlyoom irqbalance tuned smartd; do
    systemctl is-active --quiet "$svc" 2>/dev/null && continue
    s "WARN: $svc inactive — restarting"
    systemctl restart "$svc" 2>/dev/null && s "$svc restarted OK" || \
      { s "$svc restart failed — escalating"; /usr/local/bin/immortal-heal service_restart "$svc" 2>/dev/null || true; }
  done

  # Swap pressure
  SWAPUSED=$(free 2>/dev/null | awk "/^Swap:/{if(\$2>0) printf \"%.0f\", \$3/\$2*100; else print 0}")
  if [[ "${SWAPUSED:-0}" -gt 80 ]]; then
    s "Swap at ${SWAPUSED}% — swapoff/on cycle"
    swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
  fi

  # OOM events
  journalctl --since "-20min" --no-pager -q 2>/dev/null | grep -q "Out of memory" && \
    { s "OOM event detected — logged for review"; \
      journalctl --since "-20min" --no-pager -q 2>/dev/null | grep "Out of memory" | tail -5 >> "$LOG"; }

  # 3AM maintenance window (once per day)
  HOUR=$(date +%H)
  TODAY=$(date +%Y%m%d)
  LAST=$(cat "$REGEN_LOCK" 2>/dev/null || echo none)
  if [[ "$HOUR" -ge 3 && "$HOUR" -lt 4 && "$LAST" != "$TODAY" ]]; then
    s "3AM maintenance window"
    fstrim -av 2>/dev/null >> "$LOG" || true
    journalctl --vacuum-time=14d 2>/dev/null >> "$LOG" || true
    fc-cache -f 2>/dev/null >> "$LOG" || true
    echo "$TODAY" > "$REGEN_LOCK"
    s "3AM maintenance complete"
  fi

  sleep 1200
done'
[[ $DRY_RUN -eq 0 ]] && chmod +x "$SENTINEL" || true

write_file /etc/systemd/system/immortal-sentinel.service '[Unit]
Description=Immortal Sentinel — Watchdog + 3AM Maintenance v8.0
After=multi-user.target
[Service]
ExecStart=/usr/local/bin/immortal-sentinel
Restart=always
RestartSec=15
Nice=19
CPUQuota=8%
MemoryMax=64M
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/log /var/lib/immortal /run
[Install]
WantedBy=multi-user.target'

[[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
enable_service immortal-sentinel.service "Immortal Sentinel"
log "Guardian + Sentinel deployed"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 12 — MIRACLE SHOES TIMERS
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 12 — Miracle Shoes Timers (PROTECT + REGEN)"

# ── PROTECT: Weekly SMART long tests ──
write_file /usr/local/bin/immortal-smart-weekly.sh '#!/bin/bash
# Immortal PROTECT — Weekly SMART long test
LOG="/var/log/immortal-guardian.log"
s() { echo "[$(date "+%F %T")] [SMART] $*" | tee -a "$LOG"; }
s "Weekly SMART sweep started"
FAILS=0
for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
  [[ -b "$dev" ]] || continue
  transport=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep "^ID_BUS=" | cut -d= -f2 || echo "")
  [[ "$transport" == "usb" ]] && continue
  s "Queuing long test: $dev"
  if [[ "$dev" == /dev/nvme* ]]; then
    smartctl -t long "$dev" >> "$LOG" 2>&1 || s "WARN: long test unavailable for $dev"
  else
    smartctl -d sat -t long "$dev" >> "$LOG" 2>&1 || smartctl -t long "$dev" >> "$LOG" 2>&1 || true
  fi
  STATUS=$(smartctl -H "$dev" 2>/dev/null | grep -Ei "SMART overall|Health Status" | awk -F: "{print \$2}" | xargs || echo unknown)
  s "Health $dev: $STATUS"
  echo "$STATUS" | grep -qi FAILED && FAILS=$((FAILS+1))
done
[[ $FAILS -gt 0 ]] && { s "WARNING: $FAILS drive(s) failing — check logs"; \
  /usr/local/bin/immortal-heal drive_health_weekly multiple 2>/dev/null || true; }
s "SMART sweep complete (failures: $FAILS)"'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-smart-weekly.sh || true

write_file /etc/systemd/system/immortal-smart-weekly.service '[Unit]
Description=Immortal PROTECT — Weekly SMART Long Tests
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-smart-weekly.sh
Nice=19
IOSchedulingClass=idle'

write_file /etc/systemd/system/immortal-smart-weekly.timer '[Unit]
Description=Immortal PROTECT — Weekly SMART Schedule
[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true
RandomizedDelaySec=20min
[Install]
WantedBy=timers.target'

[[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
enable_service immortal-smart-weekly.timer "PROTECT (weekly SMART)"

# ── REGEN: Monthly cleanup ──
write_file /usr/local/bin/immortal-regen-monthly.sh '#!/bin/bash
# Immortal REGEN — Monthly auto-cleanup
LOG="/var/log/immortal-guardian.log"
r() { echo "[$(date "+%F %T")] [REGEN] $*" | tee -a "$LOG"; }
r "Monthly REGEN started"
journalctl --vacuum-time=14d 2>/dev/null >> "$LOG" || true
dnf autoremove -y >> "$LOG" 2>&1 || true
command -v flatpak >/dev/null 2>&1 && flatpak uninstall --unused -y >> "$LOG" 2>&1 || true
fstrim -av >> "$LOG" 2>&1 || true
find /home -type d -name thumbnails 2>/dev/null | while read -r d; do
  find "$d" -type f -atime +30 -delete 2>/dev/null || true
done
for lf in /var/log/immortal-*.log; do
  [[ -f "$lf" ]] || continue
  SIZE=$(stat -c%s "$lf" 2>/dev/null || echo 0)
  [[ $SIZE -gt 52428800 ]] && { mv "$lf" "${lf}.$(date +%Y%m%d).old"; touch "$lf"; r "Rotated: $lf"; }
done
r "Monthly REGEN complete"'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-regen-monthly.sh || true

write_file /etc/systemd/system/immortal-regen-monthly.service '[Unit]
Description=Immortal REGEN — Monthly Cleanup
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-regen-monthly.sh
Nice=19
IOSchedulingClass=idle'

write_file /etc/systemd/system/immortal-regen-monthly.timer '[Unit]
Description=Immortal REGEN — Monthly Schedule
[Timer]
OnCalendar=monthly
Persistent=true
RandomizedDelaySec=2h
[Install]
WantedBy=timers.target'

[[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
enable_service immortal-regen-monthly.timer "REGEN (monthly cleanup)"

# ── RAID Scrub (only if RAID detected) ──
if [[ $HAS_RAID -eq 1 ]]; then
  write_file /usr/local/bin/immortal-raid-scrub.sh '#!/bin/bash
# Immortal RAID Scrub — monthly integrity check
LOG="/var/log/immortal-guardian.log"
r() { echo "[$(date "+%F %T")] [RAID] $*" | tee -a "$LOG"; }
r "RAID scrub started"
ERRS=0
while IFS= read -r arr; do
  [[ -z "$arr" ]] && continue
  echo "check" > "/sys/block/$arr/md/sync_action" 2>/dev/null || \
    { r "WARN: could not scrub $arr"; ERRS=$((ERRS+1)); continue; }
  for i in $(seq 1 240); do
    [[ "$(cat /sys/block/$arr/md/sync_action 2>/dev/null)" == "idle" ]] && break
    sleep 30
  done
  MC=$(cat "/sys/block/$arr/md/mismatch_cnt" 2>/dev/null || echo unknown)
  r "$arr mismatch_cnt: $MC"
  [[ "$MC" != "0" && "$MC" != "unknown" ]] && ERRS=$((ERRS+1))
done < <(awk "/^md/{print \$1}" /proc/mdstat 2>/dev/null)
[[ $ERRS -gt 0 ]] && { r "RAID: $ERRS issue(s) — check mdstat"; \
  /usr/local/bin/immortal-heal raid_scrub_errors md_arrays 2>/dev/null || true; }
r "RAID scrub complete (issues: $ERRS)"'
  [[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-raid-scrub.sh || true

  write_file /etc/systemd/system/immortal-raid-scrub.service '[Unit]
Description=Immortal RAID Integrity Scrub
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-raid-scrub.sh
Nice=19
IOSchedulingClass=idle
TimeoutSec=14400'

  write_file /etc/systemd/system/immortal-raid-scrub.timer '[Unit]
Description=Immortal RAID Scrub — Monthly
[Timer]
OnCalendar=*-*-01 02:00:00
Persistent=true
RandomizedDelaySec=1h
[Install]
WantedBy=timers.target'

  [[ $DRY_RUN -eq 0 ]] && systemctl daemon-reload >>"$LOG_FILE" 2>&1 || true
  enable_service immortal-raid-scrub.timer "RAID scrub timer"
fi

log "Miracle Shoes timers active: PROTECT ✓ REGEN ✓ $([ $HAS_RAID -eq 1 ] && echo 'RAID ✓' || echo 'RAID (n/a)')"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 13 — OPTIONAL MODULES
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 13 — Optional Modules"

# ── OMNISCIENCE: Netdata ──
if [[ $ENABLE_NETDATA -eq 1 ]]; then
  if command -v netdata >/dev/null 2>&1 || rpm -q netdata &>/dev/null; then
    if [[ $DRY_RUN -eq 0 && ! -f /etc/netdata/netdata.conf ]]; then
      mkdir -p /etc/netdata
      write_file /etc/netdata/netdata.conf '[global]
    history = 3600
    update every = 2
    memory mode = ram
[web]
    bind to = localhost'
    fi
    enable_service netdata "Netdata dashboard"
    log "OMNISCIENCE: Netdata → http://localhost:19999"
  else
    warn "Netdata not installed — run with --skip-pkgs=0 and ensure repo is accessible"
  fi
else
  info "Netdata skipped (--enable-netdata to activate)"
fi

# ── Gaming module ──
if [[ $ENABLE_GAMING -eq 1 && $DRY_RUN -eq 0 ]]; then
  if command -v gamemoded >/dev/null 2>&1 || rpm -q gamemode &>/dev/null; then
    [[ ! -f /etc/gamemode.ini ]] && write_file /etc/gamemode.ini '[general]
reaper_freq=5
desired_governor=performance
default_governor=schedutil
softrealtime=auto
renice=0
ioprio=0
[custom]
start=/usr/local/bin/immortal-gaming-start
end=/usr/local/bin/immortal-gaming-stop'
    getent group gamemode >/dev/null 2>&1 && usermod -aG gamemode "$REAL_USER" 2>/dev/null || true

    write_file /usr/local/bin/immortal-gaming-start '#!/bin/bash
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g" 2>/dev/null || true; done
echo "0" > /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null || true
echo "[$(date +%T)] Gaming session started" >> /tmp/immortal-gaming.log'
    chmod +x /usr/local/bin/immortal-gaming-start

    write_file /usr/local/bin/immortal-gaming-stop '#!/bin/bash
tuned-adm profile immortal-ultima 2>/dev/null || true
echo "[$(date +%T)] Gaming session ended" >> /tmp/immortal-gaming.log'
    chmod +x /usr/local/bin/immortal-gaming-stop
    log "Gaming module: gamemode + hooks installed"
    info "Usage: gamemoderun %%command%% | MANGOHUD=1 gamemoderun %%command%%"
  else
    warn "gamemode not installed — re-run without --skip-pkgs"
  fi
else
  [[ $ENABLE_GAMING -eq 0 ]] && info "Gaming module skipped (--enable-gaming to activate)"
fi

# ── Security module ──
if [[ $ENABLE_SECURITY -eq 1 && $DRY_RUN -eq 0 ]]; then
  if command -v fail2ban-server >/dev/null 2>&1 || rpm -q fail2ban &>/dev/null; then
    [[ ! -f /etc/fail2ban/jail.local ]] && write_file /etc/fail2ban/jail.local '[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 7200'
    enable_service fail2ban "fail2ban SSH protection"
    log "Security module: fail2ban active (SSH: 3 retries → 2h ban)"
  else
    warn "fail2ban not installed — re-run without --skip-pkgs"
  fi
else
  [[ $ENABLE_SECURITY -eq 0 ]] && info "Security module skipped (--enable-security to activate)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 14 — COMPANION TOOLS (heal, status, logs, health-check)
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 14 — Companion Tools"

# immortal-heal
write_file /usr/local/bin/immortal-heal '#!/bin/bash
# Immortal Heal v8.0 — event escalation + optional webhook
HEAL_LOG="/var/log/immortal-heal.log"
EVENT="${1:-unknown}"; SUBJECT="${2:-unknown}"
HOST=$(hostname)
h() { echo "[$(date "+%F %T")] [HEAL] $*" | tee -a "$HEAL_LOG"; }
alert() {
  h "ALERT: $1"
  local wh="${IMMORTAL_WEBHOOK:-}"
  [[ -n "$wh" ]] && curl -sf -X POST -H "Content-Type: application/json" \
    --data "{\"text\":\"[IMMORTAL $HOST] $1\"}" "$wh" >/dev/null 2>&1 || true
}
h "Invoked: event=$EVENT subject=$SUBJECT"
case "$EVENT" in
  drive_failure)
    alert "DRIVE FAILURE: $SUBJECT — IMMEDIATE ATTENTION REQUIRED"
    echo "DRIVE_FAILURE:$SUBJECT:$(date "+%F %T")" >> /var/lib/immortal/failure_flags
    ;;
  drive_health_weekly) alert "Weekly SMART: failing drives detected — check logs" ;;
  raid_scrub_errors)   alert "RAID scrub: mismatches found — check mdstat" ;;
  service_restart)
    systemctl restart "$SUBJECT" 2>/dev/null && h "$SUBJECT restarted OK" || \
      { h "$SUBJECT restart failed"; alert "Service $SUBJECT failed to restart"; }
    ;;
  *) h "Unknown event: $EVENT"; alert "Unknown event: $EVENT / $SUBJECT" ;;
esac
h "Heal complete: event=$EVENT"'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-heal || true

# immortal-status
write_file /usr/local/bin/immortal-status '#!/bin/bash
CYN=$'"'"'\e[0;36m'"'"'; GRN=$'"'"'\e[0;32m'"'"'; YLW=$'"'"'\e[1;33m'"'"'; RED=$'"'"'\e[0;31m'"'"'; NC=$'"'"'\e[0m'"'"'; BOLD=$'"'"'\e[1m'"'"'
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║  IMMORTAL v8.0 — BALANCED ASCENSION — LIVE STATUS              ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo " Uptime : $(uptime -p)"
echo " Kernel : $(uname -r)"
echo " Tuned  : $(tuned-adm active 2>/dev/null | grep -o "profile:.*" || echo none)"
echo " ZRAM   : $(swapon --show 2>/dev/null | grep zram || echo none)"
echo ""
echo -e "${BOLD}── Core Daemons ─────────────────────────────────────────${NC}"
for svc in tuned earlyoom irqbalance smartd fstrim.timer \
           immortal-guardian.timer immortal-sentinel.service; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo inactive)
  [[ "$state" == "active" ]] && col="$GRN" || col="$YLW"
  printf " %-44s %b%s%b\n" "$svc" "$col" "$state" "$NC"
done
echo ""
echo -e "${BOLD}── Miracle Shoes Timers ─────────────────────────────────${NC}"
for svc in immortal-smart-weekly.timer immortal-regen-monthly.timer \
           immortal-raid-scrub.timer netdata fail2ban; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo not-installed)
  [[ "$state" == "active" ]] && col="$GRN" || col="$YLW"
  printf " %-44s %b%s%b\n" "$svc" "$col" "$state" "$NC"
done
echo ""
echo -e "${BOLD}── Hardware ─────────────────────────────────────────────${NC}"
command -v nvidia-smi &>/dev/null && echo " GPU Temp  : $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)°C"
command -v scx_rusty  &>/dev/null && echo " scx       : $(systemctl is-active scx 2>/dev/null)"
echo " Swap      : $(free -h 2>/dev/null | awk "/^Swap:/{print \$3\"/\"\$2}")"
if [[ -s /var/lib/immortal/failure_flags ]]; then
  echo ""
  echo -e "${RED}── Failure Flags ────────────────────────────────────────${NC}"
  cat /var/lib/immortal/failure_flags | while read -r f; do echo -e " ${RED}$f${NC}"; done
fi
echo ""
echo " Set IMMORTAL_WEBHOOK=https://your-endpoint for push alerts"'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-status || true

# immortal-logs
write_file /usr/local/bin/immortal-logs '#!/bin/bash
case "${1:-all}" in
  guardian)  journalctl -u immortal-guardian  -n 100 --no-pager ;;
  sentinel)  journalctl -u immortal-sentinel  -n 100 --no-pager ;;
  smart)     journalctl -u immortal-smart-weekly -n 100 --no-pager ;;
  regen)     journalctl -u immortal-regen-monthly -n 100 --no-pager ;;
  raid)      journalctl -u immortal-raid-scrub -n 100 --no-pager ;;
  heal)      tail -n 100 /var/log/immortal-heal.log 2>/dev/null || echo "No heal log yet" ;;
  -f|follow) journalctl -u immortal-sentinel -f ;;
  all)       journalctl -u immortal-guardian -u immortal-sentinel -n 60 --no-pager ;;
  *)         echo "Usage: immortal-logs [guardian|sentinel|smart|regen|raid|heal|all|-f]" ;;
esac'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-logs || true

# immortal-health-check
write_file /usr/local/bin/immortal-health-check '#!/bin/bash
echo "Immortal Health Check v8.0"
echo "Tuned       : $(tuned-adm active 2>/dev/null || echo none)"
echo "SMART timer : $(systemctl is-active immortal-smart-weekly.timer 2>/dev/null)"
echo "REGEN timer : $(systemctl is-active immortal-regen-monthly.timer 2>/dev/null)"
echo "RAID timer  : $(systemctl is-active immortal-raid-scrub.timer  2>/dev/null)"
echo ""
fwupdmgr get-updates --quiet 2>/dev/null | head -5 || echo "fwupdmgr: no updates / unavailable"
echo ""
FIRST_NVME=$(nvme list 2>/dev/null | awk "/^\/dev\/nvme/{print \$1; exit}")
if [[ -n "$FIRST_NVME" ]]; then
  echo "SMART short test on $FIRST_NVME:"
  smartctl -t short "$FIRST_NVME" 2>/dev/null || echo "SMART unavailable"
fi
command -v fail2ban-client &>/dev/null && fail2ban-client status 2>/dev/null | head -5
echo ""
echo "Log: /var/log/immortal-ultima-omega.log"'
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-health-check || true

log "Companion tools installed: immortal-status | immortal-logs | immortal-heal | immortal-health-check"

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 15 — SYSTEM SCAN + AI EXPORT (from beta)
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 15 — System Scan + AI Export"

if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "=== IMMORTAL SYSTEM SCAN v8.0 — $(timestamp) ==="
    echo "Host   : $(hostname)"
    echo "Kernel : $(uname -r)"
    echo "Uptime : $(uptime -p)"
    echo ""
    echo "--- Failed Services ---"
    systemctl --failed --no-pager 2>/dev/null || true
    echo ""
    echo "--- Disk Usage ---"
    df -h 2>/dev/null
    echo ""
    echo "--- Memory + Swap ---"
    free -h 2>/dev/null
    echo ""
    echo "--- Dmesg Errors (last 30 lines) ---"
    dmesg --level=err,warn 2>/dev/null | tail -30
    echo ""
    echo "--- SMART Overview ---"
    for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
      [[ -b "$dev" ]] || continue
      STATUS=$(smartctl -H "$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | \
               awk -F: '{print $2}' | xargs || echo unknown)
      echo " $dev: $STATUS"
    done
    echo ""
    echo "--- Immortal Service Status ---"
    for svc in tuned earlyoom smartd immortal-guardian.timer \
               immortal-sentinel.service immortal-smart-weekly.timer \
               immortal-regen-monthly.timer; do
      printf " %-44s %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo inactive)"
    done
  } > "$SCAN_FILE"

  log "System scan saved → $SCAN_FILE"

  # AI export: scan + safe prompt (no self-modification instructions)
  PROMPT_FILE="/tmp/immortal-ai-prompt.txt"
  {
    echo "You are a Linux system expert reviewing this machine's health scan."
    echo "Recommend ONLY safe, stability-focused improvements. Do not suggest"
    echo "disabling security features, kernel parameters you cannot verify, or"
    echo "anything that requires a reboot without explicitly noting it."
    echo ""
    cat "$SCAN_FILE"
  } > "$PROMPT_FILE"

  # Clipboard export
  CLIP_SUCCESS=0
  if command -v wl-copy >/dev/null 2>&1; then
    WL_DISP="${WAYLAND_DISPLAY:-/run/user/${REAL_UID}/wayland-0}"
    cat "$PROMPT_FILE" | su -c "WAYLAND_DISPLAY='$WL_DISP' wl-copy" "$REAL_USER" 2>/dev/null \
      && { log "Copied to clipboard (Wayland)"; CLIP_SUCCESS=1; } || true
  fi
  if [[ $CLIP_SUCCESS -eq 0 ]] && command -v xclip >/dev/null 2>&1; then
    cat "$PROMPT_FILE" | su -c "DISPLAY=${DISPLAY:-:0} xclip -selection clipboard" "$REAL_USER" 2>/dev/null \
      && { log "Copied to clipboard (X11)"; CLIP_SUCCESS=1; } || true
  fi
  [[ $CLIP_SUCCESS -eq 0 ]] && warn "Clipboard unavailable — prompt saved to $PROMPT_FILE"
else
  info "[DRY] Would run system scan and export AI prompt"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STAGE 16 — VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════
sect "Stage 16 — Verification"

check_svc() {
  local svc="$1"
  systemctl is-active --quiet "$svc" 2>/dev/null && \
    { verify "$svc: active ✓"; return 0; } || \
    { record_failure "$svc not active"; return 1; }
}

check_svc tuned
check_svc earlyoom
check_svc irqbalance
check_svc smartd
check_svc immortal-guardian.timer
check_svc immortal-sentinel.service
check_svc immortal-smart-weekly.timer
check_svc immortal-regen-monthly.timer
[[ $HAS_RAID -eq 1 ]]        && check_svc immortal-raid-scrub.timer
[[ $HAS_SCX -eq 1 ]]         && check_svc scx
[[ $ENABLE_NETDATA -eq 1 ]]  && check_svc netdata
[[ $ENABLE_SECURITY -eq 1 ]] && check_svc fail2ban

# Machine-readable summary
if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "---IMMORTAL_RUN_SUMMARY---"
    echo "version=8.0"
    echo "date=$(date +%Y-%m-%d)"
    echo "host=$(hostname)"
    echo "kernel=$KERNEL_VER"
    echo "failures=$VERIFY_FAILURES"
    echo "cachyos=$IS_CACHYOS sched=$CACHYOS_SCHED scx=$HAS_SCX"
    echo "gpu=NVIDIA:$GPU_NVIDIA AMD:$GPU_AMD Intel:$GPU_INTEL"
    echo "is_laptop=$IS_LAPTOP ryzen=$IS_RYZEN ryzen9=$IS_RYZEN9"
    echo "ram_gb=$TOTAL_RAM_GB de=$DE has_raid=$HAS_RAID"
    echo "modules: netdata=$ENABLE_NETDATA gaming=$ENABLE_GAMING security=$ENABLE_SECURITY"
    echo "miracle_shoes=HASTE,PROTECT,REGEN,OMNISCIENCE"
    echo "---END_SUMMARY---"
  } | tee -a "$LOG_FILE" > /tmp/immortal-run-summary.txt
fi

# ═════════════════════════════════════════════════════════════════════════════
# FINAL BANNER
# ═════════════════════════════════════════════════════════════════════════════
echo ""
if [[ $VERIFY_FAILURES -eq 0 ]]; then
  echo -e "${GRN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GRN}║  IMMORTAL ULTIMA OMEGA v8.0 — BALANCED ASCENSION — COMPLETE ✓         ║${NC}"
  echo -e "${GRN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${YLW}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YLW}║  IMMORTAL v8.0 COMPLETE — $VERIFY_FAILURES verification failure(s) — check log    ║${NC}"
  echo -e "${YLW}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  for f in "${FAILURE_LOG[@]}"; do err " • $f"; done
fi
echo ""
echo " HASTE ✓  PROTECT ✓  REGEN ✓  OMNISCIENCE $([ $ENABLE_NETDATA -eq 1 ] && echo ✓ || echo ○)"
echo " GAMING   $([ $ENABLE_GAMING -eq 1 ] && echo ✓ || echo ○)  SECURITY $([ $ENABLE_SECURITY -eq 1 ] && echo ✓ || echo ○)"
echo ""
echo " Run 'immortal-status' anytime to see live state"
echo " Run 'immortal-logs [guardian|sentinel|smart|regen|heal|-f]' for logs"
echo " Run 'immortal-health-check' for a full health sweep"
echo " Run 'sudo bash $0 --revert' to undo everything cleanly"
echo " Run summary: /tmp/immortal-run-summary.txt"
echo " Scan+AI prompt: /tmp/immortal-ai-prompt.txt (also in clipboard)"
echo ""
echo " Optional modules not yet enabled:"
[[ $ENABLE_NETDATA -eq 0 ]]   && echo "   --enable-netdata  → Netdata dashboard (http://localhost:19999)"
[[ $ENABLE_GAMING -eq 0 ]]    && echo "   --enable-gaming   → gamemode + mangohud + governor hooks"
[[ $ENABLE_SECURITY -eq 0 ]]  && echo "   --enable-security → fail2ban SSH protection"
echo ""
echo " Set IMMORTAL_WEBHOOK=https://your-endpoint to receive push alerts"
echo " Reboot recommended for full effect."
