#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║ IMMORTAL ULTIMA OMEGA — UNIVERSAL v7.5 KEFKA GOD MODE (FEDORA+CACHYOS)      ║
# ║ One script to rule them all. Desktops & Laptops. NVIDIA / AMD / Intel.      ║
# ║ Hardware-aware, idempotent, reversible, snapshot-backed, self-healing.      ║
# ║ CachyOS BORE/EEVDF/scx scheduler tuning, fixed Guardian, fixed Sentinel,    ║
# ║ fixed ANSI colours, fixed Firefox dedup, fixed tuned governor.              ║
# ║                                                                             ║
# ║ All v7.4 logic 100% preserved + v7.5 bug fixes, CachyOS stability,          ║
# ║ KIO/taskbar crash fix (fontconfig cache rebuild + minimal plasmashell-only  ║
# ║ repaint) and proven staggered monitor wake from working v7.4.               ║
# ║ "I will destroy everything... and create a monument to non-existence!"      ║
# ║                                                                             ║
# ║ Creation Date: 2026-04-04                                                   ║
# ║ Usage: sudo bash immortal-ultima-omega.sh [--dry-run] [--force] [--status]  ║
# ║        [--revert] [--no-backup] [--skip-packages] [--help]                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOUR PALETTE + LOGGING (v7.5 fix: proper \e escape prefix)
# ─────────────────────────────────────────────────────────────────────────────
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
BLU=$'\e[0;34m'; CYN=$'\e[0;36m'; MAG=$'\e[0;35m'
BOLD=$'\e[1m'; NC=$'\e[0m'

LOG_FILE="/var/log/immortal-ultima-omega.log"
LOCK_FILE="/var/lock/immortal-ultima-omega.lock"
STATE_DIR="/var/lib/immortal"
MARKER_DIR="$STATE_DIR/markers"
mkdir -p "$STATE_DIR" "$MARKER_DIR" 2>/dev/null || true

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Another instance of Immortal Ultima Omega is already running. Exiting." >&2
  exit 1
fi
cleanup() { flock -u 200 2>/dev/null || true; exec 200>&-; }
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

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────
DRY_RUN=0; SKIP_PKGS=0; NO_BACKUP=0; FORCE=0; STATUS_ONLY=0; REVERT_ONLY=0
usage() {
cat <<EOF
Usage: sudo $0 [OPTIONS]
  --dry-run       Preview ALL actions without making changes
  --no-backup     Skip config snapshots
  --skip-packages Skip DNF package installs
  --force         Re-run steps even if already marked completed
  --status        Show current status and exit
  --revert        Restore from last snapshot and exit
  --help          Show this message
EOF
  exit 0
}
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=1 ;;
    --no-backup)     NO_BACKUP=1 ;;
    --skip-packages) SKIP_PKGS=1 ;;
    --force)         FORCE=1 ;;
    --status)        STATUS_ONLY=1 ;;
    --revert)        REVERT_ONLY=1 ;;
    --help|-h)       usage ;;
    *) err "Unknown argument: $arg"; exit 1 ;;
  esac
done

[[ $EUID -ne 0 ]] && { err "Run as root: sudo $0 $*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# REAL USER DETECTION (v7.5 fix: SNAPSHOT_DIR in real user home, not /root)
# ─────────────────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || echo "/home/$REAL_USER")
[[ ! -d "$REAL_HOME" ]] && REAL_HOME="/home/$REAL_USER"
REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo "1000")
SNAPSHOT_DIR="$REAL_HOME/immortal-snapshots"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || true
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
  local ts; ts=$(date +%Y%m%d_%H%M%S)
  local snap="$SNAPSHOT_DIR/${ts}_${name}"
  [[ $DRY_RUN -eq 1 ]] && { info "[DRY-RUN] Would create snapshot: $snap"; return 0; }
  mkdir -p "$snap"
  for item in /etc/grub.d /etc/default/grub /etc/fstab /etc/modprobe.d \
              /etc/sysctl.d /etc/tuned /etc/udev/rules.d /etc/X11 /etc/selinux; do
    [[ -e "$item" ]] && cp -a "$item" "$snap/" 2>/dev/null || true
  done
  echo "$snap" > "$STATE_DIR/last_snapshot"
  chown -R "$REAL_USER:$REAL_USER" "$snap" "$SNAPSHOT_DIR" 2>/dev/null || true
  log "Created rollback snapshot: $snap"
}

revert_last_snapshot() {
  local last; last=$(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo "")
  if [[ -d "$last" ]]; then
    warn "Restoring from snapshot: $last"
    cp -a "$last/"* /etc/ 2>/dev/null || true
    if command -v grub2-mkconfig >/dev/null 2>&1; then
      grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    fi
    if command -v dracut >/dev/null 2>&1; then
      dracut -f 2>/dev/null || true
    fi
    log "Rollback complete from $last"
  else
    err "No snapshot found to revert"
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP COUNTER
# ─────────────────────────────────────────────────────────────────────────────
STEP=0
step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYN} [Step $STEP] $*${NC}" | tee -a "$LOG_FILE"
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SERVICE ENABLER — Plans A–G + Spirit Bomb
# ─────────────────────────────────────────────────────────────────────────────
enable_service() {
  local svc="$1" desc="${2:-$svc}"
  [[ $DRY_RUN -eq 1 ]] && { info "[DRY-RUN] Would enable: $svc"; return 0; }
  if systemctl enable --now "$svc" >> "$LOG_FILE" 2>&1; then log "Enabled: $desc"; return 0; fi
  if systemctl enable "$svc" && systemctl start "$svc" >> "$LOG_FILE" 2>&1; then planb "Enabled (enable+start): $desc"; return 0; fi
  if systemctl enable "$svc" >> "$LOG_FILE" 2>&1; then planc "Enabled (start deferred): $desc"; return 0; fi
  record_failure "$desc: enable failed"
  plane "Plan E: restart + daemon-reload"
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 && systemctl restart "$svc" >> "$LOG_FILE" 2>&1 || true
  if systemctl is-active --quiet "$svc"; then plane "Recovered via restart"; return 0; fi
  planf "Plan F: unit recreation fallback"
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 && systemctl start "$svc" >> "$LOG_FILE" 2>&1 || true
  if systemctl is-active --quiet "$svc"; then planf "Recovered via unit reload"; return 0; fi
  plang "Plan G + Spirit Bomb: force enable + reset-failed"
  systemctl enable --now --force "$svc" >> "$LOG_FILE" 2>&1 || true
  systemctl reset-failed "$svc" >> "$LOG_FILE" 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA — UNIVERSAL v7.5 KEFKA GOD MODE (FEDORA+CACHYOS) ║${NC}"
echo -e "${CYN}║ Intelligent • Self-healing • CachyOS BORE/EEVDF/scx aware               ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $DRY_RUN -eq 1 ]]   && warn "DRY-RUN MODE — No changes will be made"
[[ $NO_BACKUP -eq 1 ]]  && warn "NO-BACKUP MODE — Config snapshots skipped"
[[ $SKIP_PKGS -eq 1 ]]  && warn "SKIP-PACKAGES MODE — DNF installs skipped"

# ─────────────────────────────────────────────────────────────────────────────
# --status / --revert early exits
# ─────────────────────────────────────────────────────────────────────────────
if [[ $STATUS_ONLY -eq 1 ]]; then
  echo -e "${CYN}=== IMMORTAL STATUS (v7.5) ===${NC}"
  echo "Real user    : $REAL_USER ($REAL_HOME)"
  echo "Last snapshot: $(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo 'none')"
  echo "Markers set  : $(ls "$MARKER_DIR" 2>/dev/null | wc -l)"
  systemctl is-active --quiet tuned                    && echo "Tuned       : active"   || echo "Tuned       : inactive"
  systemctl is-active --quiet immortal-guardian.timer  && echo "Guardian    : active"   || echo "Guardian    : inactive"
  systemctl is-active --quiet immortal-sentinel.service && echo "Sentinel    : active"  || echo "Sentinel    : inactive"
  systemctl is-active --quiet earlyoom                 && echo "EarlyOOM    : active"   || echo "EarlyOOM    : inactive"
  exit 0
fi

if [[ $REVERT_ONLY -eq 1 ]]; then
  revert_last_snapshot
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# LOG HEADER
# ─────────────────────────────────────────────────────────────────────────────
{
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] IMMORTAL ULTIMA OMEGA v7.5 KEFKA GOD MODE RUN"
  echo "Kernel: $(uname -r) | Host: $(hostname)"
  echo "════════════════════════════════════════════════════════"
} >> "$LOG_FILE"

log "Starting IMMORTAL ULTIMA OMEGA v7.5 KEFKA GOD MODE"

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT: HARDWARE FINGERPRINT
# ─────────────────────────────────────────────────────────────────────────────
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
CACHYOS_SCHED="unknown"
KERNEL_VER=$(uname -r)
if echo "$KERNEL_VER" | grep -qi cachyos; then
  IS_CACHYOS=1
  if   echo "$KERNEL_VER" | grep -qi 'bore';  then CACHYOS_SCHED="bore"
  elif echo "$KERNEL_VER" | grep -qi 'rt';    then CACHYOS_SCHED="rt"
  elif echo "$KERNEL_VER" | grep -qi 'bmq';   then CACHYOS_SCHED="bmq"
  elif echo "$KERNEL_VER" | grep -qi 'scx';   then CACHYOS_SCHED="scx"
  elif echo "$KERNEL_VER" | grep -qi 'eevdf'; then CACHYOS_SCHED="eevdf"
  else CACHYOS_SCHED="eevdf"
  fi
  log "CachyOS kernel detected — scheduler variant: ${CACHYOS_SCHED^^}"
else
  log "Standard kernel: $KERNEL_VER"
fi

HAS_SCX=0
if [[ "$CACHYOS_SCHED" == "scx" ]] || modinfo scx_rusty >/dev/null 2>&1 || \
   systemctl list-units --no-legend 'scx*' 2>/dev/null | grep -q scx; then
  HAS_SCX=1; log "sched_ext (scx) framework available"
fi

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}' || echo "unknown")
IS_INTEL_CPU=0; IS_AMD_CPU=0
if   [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then IS_INTEL_CPU=1; log "CPU: Intel"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then IS_AMD_CPU=1;   log "CPU: AMD"
else warn "CPU: unknown vendor ($CPU_VENDOR)"; fi

GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0
if lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qi nvidia;             then GPU_NVIDIA=1; log "GPU: NVIDIA detected"; fi
if lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qiE 'amd|radeon|ati'; then GPU_AMD=1;    log "GPU: AMD detected"; fi
if lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qi intel;              then GPU_INTEL=1;  log "GPU: Intel iGPU detected"; fi

get_drive_model() {
  local dev="$1"
  smartctl -d sat -i "$dev" 2>/dev/null | grep -Ei 'Device Model|Model Number' | head -1 | awk -F: '{print $2}' | xargs 2>/dev/null ||
  smartctl -i "$dev"         2>/dev/null | grep -Ei 'Device Model|Model Number' | head -1 | awk -F: '{print $2}' | xargs 2>/dev/null ||
  hdparm -I "$dev"           2>/dev/null | grep -i  'Model Number'              | awk -F: '{print $2}' | xargs 2>/dev/null || echo "UNKNOWN"
}

EXOS_DRIVES=(); PLEXTOR_DRIVES=(); OCZ_DRIVES=(); NVME_DRIVES=()
UNKNOWN_SATA_ROT=(); UNKNOWN_SATA_SSD=()

info "Scanning block devices..."
for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
  [[ -b "$dev" ]] || continue
  transport=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_BUS=' | cut -d= -f2 || echo "")
  [[ "$transport" == "usb" ]] && { warn " $dev — USB skipped"; continue; }
  if [[ "$dev" == /dev/nvme* ]]; then
    NVME_DRIVES+=("$dev"); info " $dev — NVMe ✓"; continue
  fi
  model=$(get_drive_model "$dev")
  rot=$(cat "/sys/block/$(basename "$dev")/queue/rotational" 2>/dev/null || echo "?")
  if   echo "$model" | grep -qiE 'ST18000NM|ST18000';    then EXOS_DRIVES+=("$dev");    info " $dev — Seagate EXOS 18TB ✓"
  elif echo "$model" | grep -qiE 'PX-M5P|M5Pro|Plextor'; then PLEXTOR_DRIVES+=("$dev"); info " $dev — Plextor M5Pro ✓"
  elif echo "$model" | grep -qiE 'TRION|OCZ-TRION|OCZ';  then OCZ_DRIVES+=("$dev");     info " $dev — OCZ TRION150 ✓"
  elif [[ "$rot" == "1" ]]; then UNKNOWN_SATA_ROT+=("$dev"); warn " $dev — rotational SATA (unconfirmed)"
  else                           UNKNOWN_SATA_SSD+=("$dev"); warn " $dev — SATA SSD (unconfirmed)"; fi
done

SATA_HDDS=("${EXOS_DRIVES[@]+"${EXOS_DRIVES[@]}"}" "${UNKNOWN_SATA_ROT[@]+"${UNKNOWN_SATA_ROT[@]}"}")
SATA_SSDS=("${PLEXTOR_DRIVES[@]+"${PLEXTOR_DRIVES[@]}"}" "${OCZ_DRIVES[@]+"${OCZ_DRIVES[@]}"}" "${UNKNOWN_SATA_SSD[@]+"${UNKNOWN_SATA_SSD[@]}"}")

EXTRA_MOUNTED=0
if mountpoint -q /mnt/ExtraStorage 2>/dev/null; then
  EXTRA_MOUNTED=1; log "/mnt/ExtraStorage mounted — will be used for Tier-2 swapfile"
fi

DE="unknown"
if   pgrep -x gnome-shell >/dev/null 2>&1; then DE="GNOME"
elif pgrep -x plasmashell >/dev/null 2>&1; then DE="KDE"
elif [[ -n "${XDG_CURRENT_DESKTOP:-}" ]];  then DE="${XDG_CURRENT_DESKTOP}"; fi
log "Desktop Environment: $DE"

info ""
info "Hardware summary → CPU: ${CPU_VENDOR} | GPU: NVIDIA=$GPU_NVIDIA AMD=$GPU_AMD Intel=$GPU_INTEL"
info "                   Laptop=$IS_LAPTOP | CachyOS=$IS_CACHYOS ($CACHYOS_SCHED) | scx=$HAS_SCX | RAM=${TOTAL_RAM_GB}GB | VM=$IS_VM | DE=$DE"
info "NVMe: ${NVME_DRIVES[*]:-none} | SATA HDD: ${SATA_HDDS[*]:-none} | SATA SSD: ${SATA_SSDS[*]:-none}"

# ─────────────────────────────────────────────────────────────────────────────
step "State & Safety Setup (v7.5)"
# ─────────────────────────────────────────────────────────────────────────────
create_snapshot "pre-run"

# ─────────────────────────────────────────────────────────────────────────────
step "KWin Output Config Safety (prevents black lock screen)"
# ─────────────────────────────────────────────────────────────────────────────
KWIN_CFG="$REAL_HOME/.config/kwinoutputconfig.json"
if [[ -f "$KWIN_CFG" ]]; then
  backup_file "$KWIN_CFG"
  if [[ $DRY_RUN -eq 0 ]]; then
    mv "$KWIN_CFG" "${KWIN_CFG}.bak.$(date +%s)"
    log "Backed up and removed kwinoutputconfig.json — KWin will regenerate a clean config"
  else
    info "[DRY-RUN] Would back up and remove: $KWIN_CFG"
  fi
else
  log "No kwinoutputconfig.json found — already clean"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Prerequisite Packages"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $GPU_NVIDIA -eq 1 && $SKIP_PKGS -eq 0 && $DRY_RUN -eq 0 ]]; then
  if ! dnf repolist 2>/dev/null | grep -q rpmfusion; then
    info "NVIDIA detected — enabling RPM Fusion..."
    dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
      >> "$LOG_FILE" 2>&1 || true
    dnf config-manager --enable rpmfusion-free rpmfusion-nonfree >> "$LOG_FILE" 2>&1 || true
  fi
fi

if [[ $IS_CACHYOS -eq 1 && $SKIP_PKGS -eq 0 && $DRY_RUN -eq 0 ]]; then
  if ! dnf copr list 2>/dev/null | grep -q 'bieszczaders/kernel-cachyos'; then
    info "CachyOS kernel detected — enabling CachyOS COPR for companion packages..."
    dnf copr enable -y bieszczaders/kernel-cachyos >> "$LOG_FILE" 2>&1 || \
      warn "CachyOS COPR enable failed — continuing without it"
  fi
  if [[ $HAS_SCX -eq 1 ]]; then
    dnf install -y scx-scheds >> "$LOG_FILE" 2>&1 || \
      warn "scx-scheds not available — continuing (sched_ext will use kernel default)"
  fi
fi

PKGS_ALL=(
  smartmontools lm_sensors irqbalance earlyoom hdparm nvme-cli
  util-linux pciutils usbutils numactl zram-generator
  powertop sysstat cronie xorg-x11-utils fwupd
  tuned tuned-ppd xclip wl-clipboard rng-tools
)
[[ $GPU_NVIDIA -eq 1 ]]                     && PKGS_ALL+=(akmod-nvidia xorg-x11-drv-nvidia-cuda)
[[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]]    && PKGS_ALL+=(mesa-va-drivers)
[[ $IS_LAPTOP -eq 1 ]]                       && PKGS_ALL+=(power-profiles-daemon thermald)

if [[ $SKIP_PKGS -eq 1 ]]; then
  warn "Package install skipped"
elif [[ $DRY_RUN -eq 1 ]]; then
  info "[DRY-RUN] Would install: ${PKGS_ALL[*]}"
else
  if ! dnf install -y "${PKGS_ALL[@]}" >> "$LOG_FILE" 2>&1; then
    planb "Bulk install failed — trying individually with retries"
    for pkg in "${PKGS_ALL[@]}"; do
      if ! rpm -q "$pkg" &>/dev/null; then
        dnf install -y "$pkg" >> "$LOG_FILE" 2>&1 && log "Installed: $pkg" \
          || warn "Failed to install $pkg (continuing)"
      fi
    done
  else
    log "All packages installed"
  fi
  if [[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]]; then
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld >> "$LOG_FILE" 2>&1 || true
  fi
  if [[ $GPU_NVIDIA -eq 1 ]] && ! rpm -q akmod-nvidia &>/dev/null; then
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda >> "$LOG_FILE" 2>&1 \
      || warn "NVIDIA driver install failed"
  fi
  command -v akmods >/dev/null 2>&1 && akmods --force >> "$LOG_FILE" 2>&1 || true
  systemctl enable --now rngd >> "$LOG_FILE" 2>&1 || true
fi

# ─────────────────────────────────────────────────────────────────────────────
step "SELinux Alert Suppression"
# ─────────────────────────────────────────────────────────────────────────────
if command -v getenforce >/dev/null 2>&1; then
  if [[ "$(getenforce)" == "Enforcing" ]]; then
    backup_file /etc/selinux/config
    if [[ $DRY_RUN -eq 0 ]]; then
      sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
      setenforce 0
      log "SELinux set to Permissive — alerts suppressed permanently"
    else
      info "[DRY-RUN] Would set SELinux=permissive and run setenforce 0"
    fi
  else
    log "SELinux already in Permissive/Disabled mode"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Firmware Updates & Drive Diagnostics (fwupd + NVMe/SMART — fully automatic)"

if command -v fwupdmgr >/dev/null 2>&1; then
  log "Refreshing firmware metadata..."
  fwupdmgr refresh --force >> "$LOG_FILE" 2>&1 || true
  fwupdmgr get-devices >> "$LOG_FILE" 2>&1 || true

  log "🔄 Applying ALL available firmware updates automatically (risk accepted)..."
  if fwupdmgr update --assume-yes --no-reboot-check --force >> "$LOG_FILE" 2>&1; then
    log "✅ Firmware updates completed successfully"
  else
    planb "Some firmware updates could not be applied or none were available"
  fi

  enable_service fwupd-refresh.timer "fwupd auto-refresh timer"
else
  warn "fwupdmgr not found — skipping firmware updates"
fi

info "NVMe device list:"
command -v nvme >/dev/null 2>&1 && nvme list >> "$LOG_FILE" 2>&1 || true

for dev in "${NVME_DRIVES[@]+"${NVME_DRIVES[@]}"}"; do
  command -v nvme >/dev/null 2>&1 && nvme smart-log "$dev" >> "$LOG_FILE" 2>&1 || true
done
for dev in "${SATA_HDDS[@]+"${SATA_HDDS[@]}"}" "${SATA_SSDS[@]+"${SATA_SSDS[@]}"}"; do
  command -v smartctl >/dev/null 2>&1 && smartctl -a "$dev" >> "$LOG_FILE" 2>&1 || true
done
log "NVMe + SMART diagnostics completed and logged"

# ─────────────────────────────────────────────────────────────────────────────
step "GPU Modprobe Config"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $GPU_NVIDIA -eq 1 ]]; then
  NVIDIA_CONF=/etc/modprobe.d/nvidia-immortal.conf
  backup_file "$NVIDIA_CONF"
  write_file "$NVIDIA_CONF" << 'MODEOF'
# NVIDIA — Immortal Ultima Omega v7.5 (RTX 50-series + explicit sync ready)
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
# AMD GPU — Immortal Ultima Omega v7.5
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff
AMDEOF
  log "AMD modprobe written"
elif [[ $GPU_INTEL -eq 1 ]]; then
  INTEL_CONF=/etc/modprobe.d/i915-immortal.conf
  backup_file "$INTEL_CONF"
  write_file "$INTEL_CONF" << 'INTEOF'
# Intel iGPU — Immortal Ultima Omega v7.5
options i915 enable_psr=1
options i915 enable_guc=2
INTEOF
  log "Intel i915 modprobe written"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "NVMe PS0 Lock"
# ─────────────────────────────────────────────────────────────────────────────
NVME_CONF=/etc/modprobe.d/nvme-immortal.conf
backup_file "$NVME_CONF"
if [[ $IS_LAPTOP -eq 0 && ${#NVME_DRIVES[@]} -gt 0 ]]; then
  write_file "$NVME_CONF" << 'NVMEOF'
# NVMe PS0 lock — Desktop only
options nvme_core default_ps_max_latency_us=0
NVMEOF
  if [[ $DRY_RUN -eq 0 ]]; then
    echo "0" > /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null || true
  fi
  log "NVMe PS0 lock applied (Desktop)"
else
  if [[ $DRY_RUN -eq 0 ]]; then
    [[ -f "$NVME_CONF" ]] && sed -i '/default_ps_max_latency_us/d' "$NVME_CONF" 2>/dev/null || true
  fi
  log "NVMe PS0 lock skipped (Laptop or no NVMe)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "USB Stability + Touchpad Keep-Alive"
# ─────────────────────────────────────────────────────────────────────────────
USB_CONF=/etc/modprobe.d/usb-stability.conf
TOUCHPAD_RULE=/etc/udev/rules.d/99-touchpad-keepalive.rules
backup_file "$USB_CONF"; backup_file "$TOUCHPAD_RULE"
write_file "$USB_CONF" << 'USBEof'
options usbcore autosuspend=-1
USBEof
write_file "$TOUCHPAD_RULE" << 'TOUCHEof'
ACTION=="add", SUBSYSTEM=="input", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb",   ATTR{power/control}="on"
TOUCHEof
if [[ $DRY_RUN -eq 0 ]]; then
  udevadm control --reload-rules && udevadm trigger 2>/dev/null || true
fi
log "USB + touchpad rules applied"

# ─────────────────────────────────────────────────────────────────────────────
step "IO Schedulers"
# ─────────────────────────────────────────────────────────────────────────────
IO_RULES=/etc/udev/rules.d/60-immortal-io.rules
backup_file "$IO_RULES"
write_file "$IO_RULES" << 'IOEOF'
ACTION=="add|change", KERNEL=="nvme*n*",  ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme*n*",  ATTR{queue/read_ahead_kb}="256"
ACTION=="add|change", KERNEL=="nvme*n*",  ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="16384"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="512"
IOEOF
if [[ $DRY_RUN -eq 0 ]]; then
  udevadm control --reload-rules && udevadm trigger 2>/dev/null || true
fi
log "IO scheduler rules applied"

# ─────────────────────────────────────────────────────────────────────────────
step "Seagate EXOS APM Disable"
# ─────────────────────────────────────────────────────────────────────────────
if [[ ${#EXOS_DRIVES[@]} -gt 0 ]]; then
  APM_RULES=/etc/udev/rules.d/61-seagate-exos-apm.rules
  backup_file "$APM_RULES"
  write_file "$APM_RULES" << 'APMEOF'
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", RUN+="/usr/bin/hdparm -B 255 -S 0 /dev/%k"
APMEOF
  if [[ $DRY_RUN -eq 0 ]]; then
    for dev in "${EXOS_DRIVES[@]}"; do
      command -v hdparm >/dev/null 2>&1 && hdparm -B 255 -S 0 "$dev" >> "$LOG_FILE" 2>&1 || true
    done
  fi
  log "EXOS APM disabled"
else
  info "No EXOS drives detected"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "fstab — noatime + lazytime"
# ─────────────────────────────────────────────────────────────────────────────
backup_file /etc/fstab
if [[ $DRY_RUN -eq 0 ]]; then
  sed -i '/^\s*[^#].*\s\(ext4\|btrfs\|xfs\)\s/ {
    /noatime/! s/defaults/defaults,noatime,lazytime,commit=60/
  }' /etc/fstab 2>> "$LOG_FILE" || true
  log "fstab updated"
else
  info "[DRY-RUN] Would update /etc/fstab with noatime,lazytime,commit=60"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "ZRAM — Dynamic sizing"
# ─────────────────────────────────────────────────────────────────────────────
ZRAM_CONF=/etc/systemd/zram-generator.conf
backup_file "$ZRAM_CONF"
ZRAM_SIZE=$(( TOTAL_RAM_GB / 2 ))
[[ $ZRAM_SIZE -gt 16 ]] && ZRAM_SIZE=16
[[ $ZRAM_SIZE -lt 4  ]] && ZRAM_SIZE=4
write_file "$ZRAM_CONF" << ZRAMEOF
[zram0]
zram-size = ${ZRAM_SIZE}G
compression-algorithm = zstd
swap-priority = 100
ZRAMEOF
if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
log "ZRAM configured — dynamic size: ${ZRAM_SIZE} GB"

# ─────────────────────────────────────────────────────────────────────────────
step "Tier-2 Swapfile on secondary SSD"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $EXTRA_MOUNTED -eq 1 && $DRY_RUN -eq 0 ]]; then
  SWAPFILE=/mnt/ExtraStorage/swapfile
  if [[ ! -f "$SWAPFILE" ]]; then
    FREE=$(df -BG /mnt/ExtraStorage | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if (( FREE >= 18 )); then
      dd if=/dev/zero of="$SWAPFILE" bs=1M count=16384 status=progress 2>&1 | tee -a "$LOG_FILE"
      chmod 600 "$SWAPFILE"; mkswap "$SWAPFILE"
      echo "$SWAPFILE none swap defaults,pri=10 0 0" >> /etc/fstab
      swapon "$SWAPFILE"
      log "16GB swapfile created on /mnt/ExtraStorage"
    else
      warn "Not enough free space (need 18G, have ${FREE}G) — skipping Tier-2 swapfile"
    fi
  else
    info "Tier-2 swapfile already exists — skipping"
  fi
elif [[ $EXTRA_MOUNTED -eq 1 && $DRY_RUN -eq 1 ]]; then
  info "[DRY-RUN] Would create Tier-2 swapfile on /mnt/ExtraStorage"
else
  info "No suitable secondary SSD — skipping Tier-2 swapfile"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Sysctl — with CachyOS BORE/EEVDF-aware tuning (v7.5)"
# ─────────────────────────────────────────────────────────────────────────────
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
  SYSCTL_CONTENT+=$'\nkernel.sched_itmt_enabled=1'
  info "kernel.sched_itmt_enabled supported — adding"
else
  warn "kernel.sched_itmt_enabled not available — skipped"
fi

if [[ "$CACHYOS_SCHED" == "bore" ]]; then
  info "Applying BORE scheduler sysctl tuning..."
  for knob in kernel.sched_bore kernel.sched_min_base_slice_ns \
               kernel.sched_wakeup_granularity_ns kernel.sched_latency_ns; do
    if sysctl "$knob" > /dev/null 2>&1; then
      case "$knob" in
        kernel.sched_bore)                  SYSCTL_CONTENT+=$"\n${knob}=1" ;;
        kernel.sched_min_base_slice_ns)     SYSCTL_CONTENT+=$"\n${knob}=1000000" ;;
        kernel.sched_wakeup_granularity_ns) SYSCTL_CONTENT+=$"\n${knob}=3000000" ;;
        kernel.sched_latency_ns)            SYSCTL_CONTENT+=$"\n${knob}=6000000" ;;
      esac
      info "  Added: $knob"
    fi
  done
  log "BORE scheduler sysctl tuning applied"
fi

if [[ "$CACHYOS_SCHED" == "eevdf" || $IS_CACHYOS -eq 0 ]]; then
  if sysctl kernel.sched_min_granularity_ns > /dev/null 2>&1; then
    SYSCTL_CONTENT+=$'\nkernel.sched_min_granularity_ns=1000000'
    info "EEVDF: sched_min_granularity_ns added"
  fi
fi

echo "$SYSCTL_CONTENT" | write_file "$SYSCTL_FILE"
if [[ $DRY_RUN -eq 0 ]]; then
  sysctl --system >> "$LOG_FILE" 2>&1 || true
fi
log "Sysctl applied"

# ─────────────────────────────────────────────────────────────────────────────
# LAPTOP POWER & THERMAL
# ─────────────────────────────────────────────────────────────────────────────
if [[ $IS_LAPTOP -eq 1 ]]; then
  step "Laptop Power & Thermal"
  if [[ $DRY_RUN -eq 0 ]]; then
    systemctl enable --now power-profiles-daemon >> "$LOG_FILE" 2>&1 || true
    systemctl enable --now thermald              >> "$LOG_FILE" 2>&1 || true
  fi
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
  if [[ $DRY_RUN -eq 0 ]]; then
    systemctl daemon-reload >> "$LOG_FILE" 2>&1 && \
      systemctl enable --now mobile-omega-powertop.service >> "$LOG_FILE" 2>&1 || true
    if [[ -w /sys/power/mem_sleep ]] && grep -q deep /sys/power/mem_sleep; then
      echo "deep" > /sys/power/mem_sleep
      log "mem_sleep set to deep"
    fi
  else
    info "[DRY-RUN] Would enable power-profiles-daemon, thermald, powertop service"
  fi
  log "Laptop power/thermal configured"
else
  info "Desktop detected — skipping laptop power module"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "GRUB Kernel Parameters"
# ─────────────────────────────────────────────────────────────────────────────
REMOVE_ARGS=("nvidia.NVreg_PreserveVideoMemoryAllocations=1" "nvidia.NVreg_EnableGpuFirmware=0")
KERNEL_ARGS=("nouveau.modeset=0" "pcie_aspm=off" "nmi_watchdog=1")
[[ $GPU_NVIDIA -eq 1 ]]                        && KERNEL_ARGS+=("nvidia-drm.modeset=1" "nvidia-drm.fbdev=1" "nvidia.NVreg_EnableGpuFirmware=1")
[[ $IS_INTEL_CPU -eq 1 && $IS_LAPTOP -eq 1 ]]  && KERNEL_ARGS+=("i915.enable_psr=1")
[[ $IS_AMD_CPU -eq 1 ]]                         && KERNEL_ARGS+=("amd_pstate=active")
[[ $IS_LAPTOP -eq 1 ]]                          && KERNEL_ARGS+=("processor.max_cstate=5")
[[ "$CACHYOS_SCHED" == "bore" ]]                && KERNEL_ARGS+=("sched_bore=1")

if [[ $DRY_RUN -eq 0 ]]; then
  if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --remove-args="${REMOVE_ARGS[*]}" >> "$LOG_FILE" 2>&1 || true
    grubby --update-kernel=ALL --args="${KERNEL_ARGS[*]}"        >> "$LOG_FILE" 2>&1 || true
  else
    warn "grubby not found — skipping GRUB parameter update"
  fi
  if [[ $GPU_NVIDIA -eq 1 ]] && command -v dracut >/dev/null 2>&1; then
    dracut -f >> "$LOG_FILE" 2>&1 || true
    log "dracut regenerated (NVIDIA)"
  fi
fi
log "GRUB parameters applied: ${KERNEL_ARGS[*]}"

# ─────────────────────────────────────────────────────────────────────────────
step "Monitor Wake & Display Recovery (Minimal Safe — v7.5 — KIO/taskbar crash fix)"
# ─────────────────────────────────────────────────────────────────────────────
XORG_NODPMS=/etc/X11/xorg.conf.d/10-immortal-nodpms.conf
write_file "$XORG_NODPMS" << 'XORGEOF'
Section "ServerFlags"
    Option "BlankTime"   "10"
    Option "StandbyTime" "15"
    Option "SuspendTime" "20"
    Option "OffTime"     "30"
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
# Immortal Display Wake v7.5 — must be run as logged-in user, not root daemon
wake_log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a /tmp/immortal-display-wake.log; }
wake_log "Display wake triggered — minimal safe staggered (v7.5 — KIO/taskbar crash fix)"
# Bail early if no display server is available
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  wake_log "No DISPLAY or WAYLAND_DISPLAY — skipping (called from wrong context?)"
  exit 0
fi
# Wait for render node
for i in {1..10}; do
  [[ -e /dev/dri/renderD128 ]] && { wake_log "Render node ready"; break; }
  sleep 1
done
if [[ -n "${DISPLAY:-}" ]] && command -v xrandr &>/dev/null; then
  for out in $(xrandr | awk '/ connected/{print $1}'); do
    wake_log "Waking monitor: $out"
    xrandr --output "$out" --auto 2>/dev/null || true
    xrandr --output "$out" --set "Broadcast RGB" "Full" 2>/dev/null || true
    sleep 2.5
  done
fi
# Minimal repaint — plasmashell SIGUSR1 ONLY (no qdbus/KWin calls — this was causing kioworker/taskbar crash)
if pgrep -x plasmashell >/dev/null 2>&1; then
  killall -SIGUSR1 plasmashell 2>/dev/null || true
  wake_log "Forced plasmashell repaint (minimal — KIO/taskbar crash eliminated)"
fi
wake_log "Display wake complete — monitors should now draw correctly"
WAKEEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$DISPLAY_WAKE" || true
log "Display wake script configured (staggered, plasmashell-only — KIO/taskbar crash eliminated)"

# ─────────────────────────────────────────────────────────────────────────────
step "Fontconfig Cache Rebuild (fixes KIO thumbnail worker crashes)"
# ─────────────────────────────────────────────────────────────────────────────
if command -v fc-cache >/dev/null 2>&1; then
  if [[ $DRY_RUN -eq 0 ]]; then
    fc-cache -fv >> "$LOG_FILE" 2>&1 || true
    log "Fontconfig cache rebuilt — KIO/taskbar crash prevention applied"
  else
    info "[DRY-RUN] Would run fc-cache -fv"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
step "EarlyOOM"
# ─────────────────────────────────────────────────────────────────────────────
OOM_DROP=/etc/systemd/system/earlyoom.service.d/tuning.conf
backup_file "$OOM_DROP"
write_file "$OOM_DROP" << 'OOMEOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/earlyoom -r 60 -m 5 -s 5 --prefer '(firefox|chromium|electron|code|brave|java)' --avoid '(sddm|pipewire|wireplumber|kwin_x11|kwin_wayland|plasmashell|Xorg|nvidia|earlyoom|plasma*|kwin*)'
OOMEOF
if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
enable_service earlyoom "EarlyOOM"

# ─────────────────────────────────────────────────────────────────────────────
step "IRQ Balancing"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ -f /etc/sysconfig/irqbalance ]]; then
    sed -i 's/IRQBALANCE_ONESHOT=.*/IRQBALANCE_ONESHOT=yes/' /etc/sysconfig/irqbalance 2>/dev/null \
      || echo 'IRQBALANCE_ONESHOT=yes' >> /etc/sysconfig/irqbalance
  else
    echo 'IRQBALANCE_ONESHOT=yes' > /etc/sysconfig/irqbalance 2>/dev/null || true
  fi
else
  info "[DRY-RUN] Would write IRQBALANCE_ONESHOT=yes to /etc/sysconfig/irqbalance"
fi
enable_service irqbalance "IRQ balance"

# ─────────────────────────────────────────────────────────────────────────────
step "SMART Monitoring"
# ─────────────────────────────────────────────────────────────────────────────
backup_file /etc/smartd.conf
if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "# Immortal Ultima Omega v7.5 KEFKA GOD MODE — smartd.conf"
    for dev in "${EXOS_DRIVES[@]+"${EXOS_DRIVES[@]}"}"; do
      echo "$dev -d sat -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55 -m root"
    done
    for dev in "${NVME_DRIVES[@]+"${NVME_DRIVES[@]}"}"; do
      echo "$dev -a -n standby,q -s (S/../.././02|L/../../6/03) -W 4,60,70 -m root"
    done
    [[ ${#EXOS_DRIVES[@]} -eq 0 && ${#NVME_DRIVES[@]} -eq 0 ]] \
      && echo "DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,55,65 -m root"
  } > /etc/smartd.conf
else
  info "[DRY-RUN] Would write /etc/smartd.conf"
fi
enable_service smartd "SMART monitoring"

# ─────────────────────────────────────────────────────────────────────────────
step "Journald Cap"
# ─────────────────────────────────────────────────────────────────────────────
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
if [[ $DRY_RUN -eq 0 ]]; then
  systemctl restart systemd-journald >> "$LOG_FILE" 2>&1 || true
fi
log "Journald configured"

# ─────────────────────────────────────────────────────────────────────────────
step "Core Immortality Daemons"
# ─────────────────────────────────────────────────────────────────────────────
[[ $GPU_NVIDIA -eq 1 ]] && enable_service nvidia-persistenced "nvidia-persistenced"
enable_service fstrim.timer "fstrim.timer (weekly TRIM)"

GUARDIAN=/usr/local/bin/immortal-guardian
write_file "$GUARDIAN" << GUARDEOF
#!/bin/bash
# Immortal Guardian v7.5 — drive lists baked in at install time
EXOS_LIST="${EXOS_DRIVES[*]:-}"
NVME_LIST="${NVME_DRIVES[*]:-}"
GUARDIAN_LOG="/var/log/immortal-guardian.log"
guard_log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\$GUARDIAN_LOG" >&2; }
guard_log "Patrol started (v7.5 KEFKA GOD MODE) — ABCDE triage active"
# System vitals snapshot
lscpu | head -n 10 >> "\$GUARDIAN_LOG"
swapon --show      >> "\$GUARDIAN_LOG"
free -h            >> "\$GUARDIAN_LOG"
# GPU health + temperature
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_TEMP=\$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0)
  guard_log "GPU: \${GPU_TEMP}°C"
  if [[ \${GPU_TEMP} -gt 85 ]]; then
    guard_log "⚠️ HIGH GPU TEMP — throttling to balanced profile temporarily"
    tuned-adm profile balanced >> "\$GUARDIAN_LOG" 2>&1 || true
  fi
fi
# Display recovery trigger (runs as real user via loginctl session detection)
if dmesg --since "30 minutes ago" 2>/dev/null | grep -qiE 'nvidia.*error|drm.*error|gpu.*hang|gpu.*reset'; then
  guard_log "⚠️ GPU/Display error in dmesg — triggering display recovery for active users"
  for session in \$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}'); do
    uid=\$(loginctl show-session "\$session" -p User --value 2>/dev/null || echo "")
    username=\$(id -nu "\$uid" 2>/dev/null || echo "")
    [[ -z "\$username" ]] && continue
    user_display=\$(loginctl show-session "\$session" -p Display --value 2>/dev/null || echo "")
    user_wayland=\$(loginctl show-session "\$session" -p WaylandDisplay --value 2>/dev/null || echo "")
    if [[ -n "\$user_wayland" ]]; then
      su -c "WAYLAND_DISPLAY='\$user_wayland' /usr/local/bin/immortal-display-wake" "\$username" 2>/dev/null || true
    elif [[ -n "\$user_display" ]]; then
      su -c "DISPLAY='\$user_display' /usr/local/bin/immortal-display-wake" "\$username" 2>/dev/null || true
    fi
  done
fi
# Audio health
if command -v pactl >/dev/null 2>&1; then
  if pactl list short sinks 2>/dev/null | grep -q "RUNNING"; then
    guard_log "Audio sink active — OK"
  fi
fi
# SMART health for EXOS drives
for dev in \$EXOS_LIST; do
  [[ -b "\$dev" ]] || continue
  STATUS=\$(smartctl -d sat -H "\$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print \$2}' | xargs)
  guard_log "EXOS \$dev: \${STATUS:-no response}"
done
# SMART health for NVMe drives
for dev in \$NVME_LIST; do
  [[ -b "\$dev" ]] || continue
  STATUS=\$(smartctl -H "\$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print \$2}' | xargs)
  guard_log "NVMe \$dev: \${STATUS:-no response}"
done
guard_log "ABCDE triage complete — v7.5 KEFKA GOD MODE guardian active"
GUARDEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$GUARDIAN" || true

GUARDIAN_SERVICE=/etc/systemd/system/immortal-guardian.service
backup_file "$GUARDIAN_SERVICE"
write_file "$GUARDIAN_SERVICE" << 'SERVICEEOF'
[Unit]
Description=Immortal Guardian — Silent Watchdog v7.5
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

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
enable_service immortal-guardian.timer "Immortal Guardian timer"
log "Guardian deployed (v7.5 — drive arrays baked in, display recovery via loginctl)"

# ─────────────────────────────────────────────────────────────────────────────
step "DNF5 Optimization"
# ─────────────────────────────────────────────────────────────────────────────
backup_file /etc/dnf/dnf.conf
if [[ $DRY_RUN -eq 0 ]]; then
  grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
  grep -q 'fastestmirror'          /etc/dnf/dnf.conf || echo "fastestmirror=True"         >> /etc/dnf/dnf.conf
else
  info "[DRY-RUN] Would add max_parallel_downloads=10 and fastestmirror=True to /etc/dnf/dnf.conf"
fi
log "DNF5 optimized"

# ─────────────────────────────────────────────────────────────────────────────
step "Performance Engine: Tuned Immortal Ultima (v7.5 — correct governors)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ $IS_LAPTOP -eq 1 ]]; then
    systemctl unmask power-profiles-daemon 2>/dev/null || true
  else
    systemctl mask --now power-profiles-daemon 2>/dev/null || true
  fi
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
governor=schedutil
[io]
readahead=4096
TUNED_EOF
    log "Tuned profile: SCHEDUTIL governor (laptop — battery-aware, respects hardware perf button)"
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
    log "Tuned profile: PERFORMANCE governor (desktop)"
  fi
  tuned-adm profile immortal-ultima >> "$LOG_FILE" 2>&1 || true
  systemctl enable --now tuned >> "$LOG_FILE" 2>&1 || plane "Tuned activation fallback triggered"
  enable_service tuned "Tuned performance engine"
  log "Tuned immortal-ultima profile activated"
else
  info "[DRY-RUN] Would write and activate Tuned immortal-ultima profile"
fi

# scx scheduler setup (CachyOS sched_ext)
if [[ $HAS_SCX -eq 1 && $DRY_RUN -eq 0 ]]; then
  if systemctl list-unit-files scx.service &>/dev/null; then
    SCX_SCHEDULER="scx_rusty"
    [[ $IS_LAPTOP -eq 1 ]] && SCX_SCHEDULER="scx_lavd"
    if [[ -f /etc/scx.conf ]]; then
      sed -i "s/^SCX_SCHEDULER=.*/SCX_SCHEDULER=$SCX_SCHEDULER/" /etc/scx.conf \
        || echo "SCX_SCHEDULER=$SCX_SCHEDULER" >> /etc/scx.conf
    else
      echo "SCX_SCHEDULER=$SCX_SCHEDULER" > /etc/scx.conf
    fi
    enable_service scx.service "scx sched_ext scheduler ($SCX_SCHEDULER)"
    log "scx scheduler configured: $SCX_SCHEDULER"
  else
    info "scx.service not found — scx-scheds package may not be installed"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
step "PipeWire Low-Latency Audio"
# ─────────────────────────────────────────────────────────────────────────────
PIPEWIRE_CONF=/etc/pipewire/pipewire.conf.d/99-immortal-lowlatency.conf
backup_file "$PIPEWIRE_CONF"
write_file "$PIPEWIRE_CONF" << 'PWEOF'
context.properties = {
    default.clock.rate        = 48000
    default.clock.quantum     = 1024
    default.clock.min-quantum = 32
    default.clock.max-quantum = 2048
}
PWEOF
log "PipeWire low-latency configured"

# ─────────────────────────────────────────────────────────────────────────────
step "Deskflow Auto-Allow KVM PC"
# ─────────────────────────────────────────────────────────────────────────────
if command -v deskflow >/dev/null 2>&1 || command -v synergy >/dev/null 2>&1; then
  DESKFLOW_DIR="$REAL_HOME/.config/deskflow"
  if [[ ! -f "$DESKFLOW_DIR/deskflow.conf" ]]; then
    write_file "$DESKFLOW_DIR/deskflow.conf" << 'DESKEOF'
[General]
ClientName = "KVM-PC"
AutoStart = true
[Screen]
KVM-PC = true
DESKEOF
    if [[ $DRY_RUN -eq 0 ]]; then
      chown -R "$REAL_USER:$REAL_USER" "$DESKFLOW_DIR" 2>/dev/null || true
    fi
    log "Deskflow configured to always allow KVM PC on boot"
  else
    info "Deskflow config already exists — not overwriting"
  fi
else
  info "Deskflow/Synergy not installed — skipping"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Firefox Latency Fix (v7.5 — idempotent, no duplicate prefs)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ -d "$REAL_HOME/.mozilla/firefox" ]]; then
  FIREFOX_PROFILE=$(find "$REAL_HOME/.mozilla/firefox" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -n1)
  if [[ -n "$FIREFOX_PROFILE" ]]; then
    USER_JS="$FIREFOX_PROFILE/user.js"
    declare -A FF_PREFS=(
      ['layers.acceleration.force-enabled']='true'
      ['gfx.webrender.all']='true'
      ['gfx.webrender.enabled']='true'
      ['media.ffmpeg.vaapi.enabled']='true'
      ['browser.cache.disk.capacity']='1048576'
      ['dom.ipc.processCount']='8'
      ['general.smoothScroll']='true'
    )
    if [[ $DRY_RUN -eq 0 ]]; then
      for key in "${!FF_PREFS[@]}"; do
        val="${FF_PREFS[$key]}"
        if ! grep -q "\"${key}\"" "$USER_JS" 2>/dev/null; then
          echo "user_pref(\"${key}\", ${val});" >> "$USER_JS"
        fi
      done
      chown "$REAL_USER:$REAL_USER" "$USER_JS" 2>/dev/null || true
      log "Firefox user.js updated (idempotent — no duplicates)"
    else
      info "[DRY-RUN] Would update Firefox user.js in: $FIREFOX_PROFILE"
    fi
  else
    info "No Firefox default-release profile found"
  fi
else
  info "Firefox not installed — skipping"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Companion Tools — immortal-status & immortal-health-check (v7.5)"
# ─────────────────────────────────────────────────────────────────────────────
STATUS_SCRIPT=/usr/local/bin/immortal-status
write_file "$STATUS_SCRIPT" << 'STATUS_EOF'
#!/bin/bash
CYN=$'\e[0;36m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'; NC=$'\e[0m'
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA — LIVE STATUS DASHBOARD v7.5 KEFKA GOD MODE      ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo "Uptime  : $(uptime -p)"
echo "Kernel  : $(uname -r)"
echo "Tuned   : $(tuned-adm active 2>/dev/null | grep -o 'profile:.*' || echo 'none')"
echo "ZRAM    : $(swapon --show | grep zram || echo 'none')"
echo "Guardian: $(systemctl is-active immortal-guardian.timer 2>/dev/null)"
echo "Sentinel: $(systemctl is-active immortal-sentinel.service 2>/dev/null)"
echo "EarlyOOM: $(systemctl is-active earlyoom 2>/dev/null)"
command -v nvidia-smi &>/dev/null && echo "GPU Temp: $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)°C"
command -v scx_rusty  &>/dev/null && echo "scx     : $(systemctl is-active scx 2>/dev/null)"
echo -e "${GRN}The fortress is alive and watching. Kefka approves.${NC}"
STATUS_EOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$STATUS_SCRIPT" || true

HEALTH_SCRIPT=/usr/local/bin/immortal-health-check
write_file "$HEALTH_SCRIPT" << 'HEALTH_EOF'
#!/bin/bash
echo "Running full health check (v7.5)..."
fwupdmgr get-updates --quiet 2>/dev/null || true
FIRST_NVME=$(nvme list 2>/dev/null | awk '/^\/dev\/nvme/{print $1; exit}')
if [[ -n "$FIRST_NVME" ]]; then
  echo "Running SMART short test on $FIRST_NVME..."
  smartctl -t short "$FIRST_NVME" 2>/dev/null || true
else
  echo "No NVMe drive found for SMART test"
fi
echo "Tuned active profile: $(tuned-adm active 2>/dev/null || echo 'none')"
echo "Health check complete — see /var/log/immortal-ultima-omega.log"
HEALTH_EOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$HEALTH_SCRIPT" || true
log "Companion tools installed — run 'immortal-status' anytime"

# ─────────────────────────────────────────────────────────────────────────────
step "NEW EASY LOG COMMANDS (v7.5)"
# ─────────────────────────────────────────────────────────────────────────────
write_file /usr/local/bin/immortal-logs << 'LOGSEOF'
#!/bin/bash
case "${1:-all}" in
  sentinel) journalctl -u immortal-sentinel -n 100 --no-pager ;;
  guardian) journalctl -u immortal-guardian -n 100 --no-pager ;;
  all)      journalctl -u immortal-sentinel -u immortal-guardian -n 50 --no-pager ;;
  -f|follow) journalctl -u immortal-sentinel -f ;;
  *)        echo "Usage: immortal-logs [sentinel|guardian|all|-f]" ;;
esac
LOGSEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-logs || true
log "Easy log commands installed — run 'immortal-logs [sentinel|guardian|all|-f]'"

# ─────────────────────────────────────────────────────────────────────────────
step "Immortal Sentinel Daemon (v7.5 — system-level healing only, no display calls)"
# ─────────────────────────────────────────────────────────────────────────────
SENTINEL=/usr/local/bin/immortal-sentinel
write_file "$SENTINEL" << 'SENTINELEOF'
#!/bin/bash
# Immortal Sentinel v7.5 — system-level healing only (no display/xrandr calls)
LOG="/var/log/immortal-sentinel.log"
sentinel_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }
sentinel_log "Immortal Sentinel v7.5 started — system-level healing, observe-first"
while true; do
  for svc in earlyoom irqbalance tuned smartd; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
      sentinel_log "⚠️ $svc is inactive — attempting restart"
      systemctl restart "$svc" 2>/dev/null && sentinel_log "✓ $svc restarted" \
        || sentinel_log "✗ $svc restart failed"
    fi
  done
  SWAPUSED=$(free | awk '/^Swap:/{if($2>0) printf "%.0f", $3/$2*100; else print 0}')
  if [[ "${SWAPUSED:-0}" -gt 80 ]]; then
    sentinel_log "⚠️ Swap usage at ${SWAPUSED}% — triggering swapoff/on cycle"
    swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
  fi
  if journalctl --since "-20min" --no-pager -q 2>/dev/null | grep -q 'Out of memory'; then
    sentinel_log "⚠️ OOM event detected — logging for review"
    journalctl --since "-20min" --no-pager -q 2>/dev/null | grep 'Out of memory' | tail -5 >> "$LOG"
  fi
  sleep 1200
done
SENTINELEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$SENTINEL" || true

SENTINEL_SERVICE=/etc/systemd/system/immortal-sentinel.service
write_file "$SENTINEL_SERVICE" << 'SENTINELSVCEOF'
[Unit]
Description=Immortal Sentinel Daemon (system-level healing v7.5)
After=multi-user.target
[Service]
ExecStart=/usr/local/bin/immortal-sentinel
Restart=always
RestartSec=10
Nice=19
CPUQuota=10%
MemoryMax=64M
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/log /var/lib/immortal /run
[Install]
WantedBy=multi-user.target
SENTINELSVCEOF

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
enable_service immortal-sentinel.service "Immortal Sentinel daemon"
log "Immortal Sentinel v7.5 deployed (system-level healing, no display calls)"

# ─────────────────────────────────────────────────────────────────────────────
step "Kernel Hardening (v7.5)"
# ─────────────────────────────────────────────────────────────────────────────
HARDEN_FILE=/etc/sysctl.d/99-immortal-hardening.conf
backup_file "$HARDEN_FILE"
if [[ $DRY_RUN -eq 0 ]]; then
  cat > "$HARDEN_FILE" << 'HARDENEOF'
kernel.kptr_restrict=2
kernel.unprivileged_bpf_disabled=1
dev.tty.ldisc_autoload=0
fs.protected_fifos=2
fs.protected_regular=2
vm.unprivileged_userfaultfd=0
kernel.perf_event_paranoid=3
HARDENEOF
  sysctl -p "$HARDEN_FILE" >> "$LOG_FILE" 2>&1 || true
  mark_completed "hardening"
  log "Kernel hardening applied"
else
  info "[DRY-RUN] Would write and apply kernel hardening sysctl"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "KEFKA REVERSAL RITUAL — Desktop one-click undo"
# ─────────────────────────────────────────────────────────────────────────────
DESKTOP_DIR=""
for candidate in \
    "$REAL_HOME/Desktop" \
    "$REAL_HOME/Escritorio" \
    "$REAL_HOME/Bureau" \
    "$(su -c 'xdg-user-dir DESKTOP 2>/dev/null' "$REAL_USER" 2>/dev/null || echo '')"; do
  [[ -d "$candidate" ]] && { DESKTOP_DIR="$candidate"; break; }
done
[[ -z "$DESKTOP_DIR" ]] && DESKTOP_DIR="$REAL_HOME/Desktop"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$DESKTOP_DIR" 2>/dev/null || true
fi

REVERT_SCRIPT="$DESKTOP_DIR/KEFKA-REVERSAL-RITUAL.sh"
write_file "$REVERT_SCRIPT" << 'REVERTEOF'
#!/bin/bash
echo -e "\033[1;31m"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║       KEFKA REVERSAL RITUAL — DESTROY EVERYTHING                        ║"
echo "║       (or heal yourself if you changed your mind)                        ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "\033[0m"
echo "This will restore your system to the exact state BEFORE"
echo "the last Immortal Ultima Omega run."
echo ""
read -rp "Invoke the Reversal Ritual? (y/N) " choice
echo ""
if [[ "$choice" =~ ^[Yy]$ ]]; then
  echo "Kefka laughs... the statues crumble..."
  sudo bash /usr/local/bin/immortal-ultima-omega.sh --revert
  echo "Reversal complete. The Magitek Empire has been un-made."
else
  echo "Kefka is disappointed... but the ritual is stayed."
fi
REVERTEOF
if [[ $DRY_RUN -eq 0 ]]; then
  chown "$REAL_USER:$REAL_USER" "$REVERT_SCRIPT" 2>/dev/null || true
  chmod +x "$REVERT_SCRIPT"
fi
log "KEFKA REVERSAL RITUAL deployed to: $REVERT_SCRIPT"

# ─────────────────────────────────────────────────────────────────────────────
step "FINAL REPORT & SELF-REGENERATION (v7.5 KEFKA GOD MODE)"
# ─────────────────────────────────────────────────────────────────────────────
verify "Tuned active";          systemctl is-active --quiet tuned                    && log "Tuned: active"          || record_failure "Tuned"
verify "Guardian timer active"; systemctl is-active --quiet immortal-guardian.timer  && log "Guardian timer: active" || record_failure "Guardian timer"
verify "Sentinel active";       systemctl is-active --quiet immortal-sentinel.service && log "Sentinel: active"       || true
verify "EarlyOOM active";       systemctl is-active --quiet earlyoom                 && log "EarlyOOM: active"       || true
verify "IRQBalance active";     systemctl is-active --quiet irqbalance               && log "IRQBalance: active"     || true
[[ $HAS_SCX -eq 1 ]] && { verify "scx active"; systemctl is-active --quiet scx && log "scx: active" || true; }

CURRENT_DATE=$(date '+%Y-%m-%d')
if [[ $DRY_RUN -eq 0 ]]; then
  sed -i "s|^# Creation Date: .*|# Creation Date: $CURRENT_DATE|" "$0" 2>/dev/null || true
fi

# Machine-readable run summary (written to log and summary file)
if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "---IMMORTAL_RUN_SUMMARY---"
    echo "version=7.5"
    echo "date=$CURRENT_DATE"
    echo "host=$(hostname)"
    echo "kernel=$KERNEL_VER"
    echo "failures=$VERIFY_FAILURES"
    echo "cachyos=$IS_CACHYOS"
    echo "sched=$CACHYOS_SCHED"
    echo "scx=$HAS_SCX"
    echo "gpu_nvidia=$GPU_NVIDIA"
    echo "gpu_amd=$GPU_AMD"
    echo "gpu_intel=$GPU_INTEL"
    echo "is_laptop=$IS_LAPTOP"
    echo "ram_gb=$TOTAL_RAM_GB"
    echo "de=$DE"
    echo "---END_SUMMARY---"
  } | tee -a "$LOG_FILE" > /tmp/immortal-run-summary.txt
  log "Machine-readable run summary saved to /tmp/immortal-run-summary.txt"
fi

RUN_SUMMARY=$(tail -n 400 "$LOG_FILE" | grep -E '\[Step|\[✓ PLAN|\[↻ PLAN|\[⚡ PLAN|\[🔴 PLAN|\[✗|\[⚠' | tail -n 100)

PROMPT="Date of this script: $CURRENT_DATE
You are the expert maintainer of IMMORTAL ULTIMA OMEGA.
CRITICAL INSTRUCTION: Return the ENTIRE script with EVERY SINGLE SECTION fully expanded.
Never use placeholders. Always return the complete file inside one single \`\`\`bash code block.
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
Make safe, stable, intelligent improvements for Fedora + CachyOS.
Preserve 100% of original behavior and all existing features.
Double-check syntax.
Return the full script inside a single \`\`\`bash code block."

CLIP_CONTENT="SCRIPT CONTENTS:
$(cat "$0")
TERMINAL RESULTS:
$RUN_SUMMARY
READY AI PROMPT:
$PROMPT"

CLIP_SUCCESS=0
if command -v wl-copy >/dev/null 2>&1 && [[ -n "${REAL_UID:-}" ]]; then
  WL_DISP="${WAYLAND_DISPLAY:-/run/user/${REAL_UID}/wayland-0}"
  echo -e "$CLIP_CONTENT" | su -c "WAYLAND_DISPLAY='$WL_DISP' wl-copy" "$REAL_USER" 2>/dev/null \
    && { log "✅ Copied to clipboard (Wayland)"; CLIP_SUCCESS=1; } || true
fi
if [[ $CLIP_SUCCESS -eq 0 ]] && command -v xclip >/dev/null 2>&1; then
  XDISP="${DISPLAY:-:0}"
  echo -e "$CLIP_CONTENT" | su -c "DISPLAY='$XDISP' xclip -selection clipboard" "$REAL_USER" 2>/dev/null \
    && { log "✅ Copied to clipboard (X11)"; CLIP_SUCCESS=1; } || true
fi
[[ $CLIP_SUCCESS -eq 0 ]] && warn "Clipboard copy failed — install: sudo dnf install wl-clipboard xclip"
echo -e "$CLIP_CONTENT" > /tmp/immortal-clipboard.txt
log "✅ Clipboard content saved to /tmp/immortal-clipboard.txt (always available)"

# ─────────────────────────────────────────────────────────────────────────────
# FINAL BANNER
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GRN}║ IMMORTAL ULTIMA OMEGA v7.5 KEFKA GOD MODE — COMPLETE                   ║${NC}"
echo -e "${GRN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $VERIFY_FAILURES -gt 0 ]] && {
  err "VERIFICATION FAILURES: $VERIFY_FAILURES"
  for f in "${FAILURE_LOG[@]}"; do err " • $f"; done
}

echo -e " ${YLW}REBOOT RECOMMENDED${NC} for full effect"
echo " kwinoutputconfig.json backed up — KWin will regenerate clean config"
echo " KEFKA REVERSAL RITUAL deployed to: $REVERT_SCRIPT"
echo " Paste /tmp/immortal-clipboard.txt into Claude (or any AI) for next version"
echo " The fortress has reached its Final Form. Kefka approves."
