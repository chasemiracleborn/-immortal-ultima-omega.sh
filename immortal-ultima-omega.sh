#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║ IMMORTAL ULTIMA OMEGA — UNIVERSAL v7.6 KEFKA GOD MODE (FEDORA+CACHYOS)      ║
# ║ "MIRACLE SHOES" release — Haste · Protect · Regen · Omniscience            ║
# ║ One script to rule them all. Desktops & Laptops. NVIDIA / AMD / Intel.      ║
# ║ Hardware-aware, idempotent, reversible, snapshot-backed, self-healing.      ║
# ║ CachyOS BORE/EEVDF/scx scheduler tuning · Ryzen fiber latency tuning        ║
# ║ Weekly SMART long tests · Monthly auto-cleanup · Netdata dashboard           ║
# ║ Plasmashell QML-cache auto-revive · 3 AM maintenance window in Sentinel     ║
# ║ Atomic snapshot manifests (sha256) · verified rollback · immortal-heal.sh   ║
# ║ Optional: --enable-netdata --enable-gaming --enable-security                ║
# ║ "I will destroy everything... and create a monument to non-existence!"      ║
# ║                                                                             ║
# ║ Creation Date: 2026-04-04                                                   ║
# ║ Usage: sudo bash immortal-ultima-omega.sh [--dry-run] [--force] [--status]  ║
# ║        [--revert] [--no-backup] [--skip-packages] [--enable-netdata]        ║
# ║        [--enable-gaming] [--enable-security] [--help]                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLOUR PALETTE + LOGGING
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
cleanup() { flock -u 200 2>/dev/null || true; exec 200>&- 2>/dev/null || true; }
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
ENABLE_NETDATA=0; ENABLE_GAMING=0; ENABLE_SECURITY=0
usage() {
cat <<EOF
Usage: sudo $0 [OPTIONS]
  --dry-run          Preview ALL actions without making changes
  --no-backup        Skip config snapshots
  --skip-packages    Skip DNF package installs
  --force            Re-run steps even if already marked completed
  --status           Show current status and exit
  --revert           Restore from last snapshot and exit
  --enable-netdata   Install and enable Netdata real-time dashboard
  --enable-gaming    Install gamemode + mangohud + gaming optimizations
  --enable-security  Install fail2ban + SSH brute-force protection
  --help             Show this message
EOF
  exit 0
}
for arg in "$@"; do
  case "$arg" in
    --dry-run)         DRY_RUN=1 ;;
    --no-backup)       NO_BACKUP=1 ;;
    --skip-packages)   SKIP_PKGS=1 ;;
    --force)           FORCE=1 ;;
    --status)          STATUS_ONLY=1 ;;
    --revert)          REVERT_ONLY=1 ;;
    --enable-netdata)  ENABLE_NETDATA=1 ;;
    --enable-gaming)   ENABLE_GAMING=1 ;;
    --enable-security) ENABLE_SECURITY=1 ;;
    --help|-h)         usage ;;
    *) err "Unknown argument: $arg"; exit 1 ;;
  esac
done

[[ $EUID -ne 0 ]] && { err "Run as root: sudo $0 $*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# REAL USER DETECTION
# ─────────────────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$REAL_USER")
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
  cp -p "$file" "${BACKUP_DIR}${file}" 2>/dev/null && info " Backed up: $file" || true
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

# safe_write — atomic idempotent append: skips if marker already present
# Usage: safe_write "/path/to/file" "marker-string" <<'EOF' ... EOF
safe_write() {
  local target="$1"
  local marker="$2"
  local content
  content=$(cat)
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e " ${YLW}[DRY-RUN]${NC} Would safe_write marker '${marker}' to: $target"
    return 0
  fi
  if grep -qF "$marker" "$target" 2>/dev/null; then
    info "Already present in $target: $marker"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  local tmp; tmp=$(mktemp)
  echo "$content" > "$tmp"
  cat "$tmp" >> "$target"
  rm -f "$tmp"
  info "safe_write applied '$marker' → $target"
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
  # Generate sha256 manifest for verified rollback
  ( cd "$snap" && find . -type f ! -name 'manifest.sha256' -print0 \
      | sort -z | xargs -0 sha256sum 2>/dev/null > "$snap/manifest.sha256" ) || true
  chown -R "$REAL_USER:$REAL_USER" "$snap" "$SNAPSHOT_DIR" 2>/dev/null || true
  log "Created rollback snapshot: $snap (manifest: $(wc -l < "$snap/manifest.sha256" 2>/dev/null || echo '?') files)"
}

revert_last_snapshot() {
  local last; last=$(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo "")
  if [[ -d "$last" ]]; then
    warn "Restoring from snapshot: $last"
    # Verify manifest before restore
    if [[ -f "$last/manifest.sha256" ]]; then
      info "Verifying snapshot manifest integrity..."
      pushd "$last" >/dev/null 2>&1
      if sha256sum -c manifest.sha256 --quiet 2>/dev/null; then
        log "Snapshot manifest verified OK — proceeding with restore"
      else
        warn "Snapshot manifest has mismatches — restoring anyway with caution"
      fi
      popd >/dev/null 2>&1
    else
      warn "No manifest found for snapshot $last — proceeding without verification"
    fi
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
  if { systemctl enable "$svc" >> "$LOG_FILE" 2>&1 && systemctl start "$svc" >> "$LOG_FILE" 2>&1; }; then planb "Enabled (enable+start): $desc"; return 0; fi
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
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA v7.6 — KEFKA GOD MODE — MIRACLE SHOES RELEASE    ║${NC}"
echo -e "${CYN}║ Haste · Protect · Regen · Omniscience · CachyOS BORE/EEVDF/scx aware   ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $DRY_RUN -eq 1 ]]       && warn "DRY-RUN MODE — No changes will be made"
[[ $NO_BACKUP -eq 1 ]]     && warn "NO-BACKUP MODE — Config snapshots skipped"
[[ $SKIP_PKGS -eq 1 ]]     && warn "SKIP-PACKAGES MODE — DNF installs skipped"
[[ $ENABLE_NETDATA -eq 1 ]] && info "NETDATA MODE — Dashboard will be installed"
[[ $ENABLE_GAMING -eq 1 ]]  && info "GAMING MODULE — gamemode + mangohud will be installed"
[[ $ENABLE_SECURITY -eq 1 ]] && info "SECURITY MODULE — fail2ban will be installed"

# ─────────────────────────────────────────────────────────────────────────────
# --status / --revert early exits
# ─────────────────────────────────────────────────────────────────────────────
if [[ $STATUS_ONLY -eq 1 ]]; then
  echo -e "${CYN}=== IMMORTAL STATUS (v7.6 — MIRACLE SHOES) ===${NC}"
  echo "Real user    : $REAL_USER ($REAL_HOME)"
  echo "Last snapshot: $(cat "$STATE_DIR/last_snapshot" 2>/dev/null || echo 'none')"
  echo "Markers set  : $(ls "$MARKER_DIR" 2>/dev/null | wc -l)"
  systemctl is-active --quiet tuned                           && echo "Tuned        : active"  || echo "Tuned        : inactive"
  systemctl is-active --quiet immortal-guardian.timer         && echo "Guardian     : active"  || echo "Guardian     : inactive"
  systemctl is-active --quiet immortal-sentinel.service       && echo "Sentinel     : active"  || echo "Sentinel     : inactive"
  systemctl is-active --quiet earlyoom                        && echo "EarlyOOM     : active"  || echo "EarlyOOM     : inactive"
  systemctl is-active --quiet immortal-smart-weekly.timer     && echo "SMART Protect: active"  || echo "SMART Protect: inactive"
  systemctl is-active --quiet immortal-regen-monthly.timer    && echo "Regen Monthly: active"  || echo "Regen Monthly: inactive"
  systemctl is-active --quiet netdata 2>/dev/null             && echo "Netdata      : active"  || echo "Netdata      : not installed"
  systemctl is-active --quiet immortal-raid-scrub.timer 2>/dev/null && echo "RAID Scrub   : active" || echo "RAID Scrub   : inactive/not configured"
  systemctl is-active --quiet fail2ban 2>/dev/null            && echo "fail2ban     : active"  || echo "fail2ban     : not installed"
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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] IMMORTAL ULTIMA OMEGA v7.6 KEFKA GOD MODE RUN"
  echo "Kernel: $(uname -r) | Host: $(hostname)"
  echo "Flags: DRY_RUN=$DRY_RUN ENABLE_NETDATA=$ENABLE_NETDATA ENABLE_GAMING=$ENABLE_GAMING ENABLE_SECURITY=$ENABLE_SECURITY"
  echo "════════════════════════════════════════════════════════"
} >> "$LOG_FILE"

log "Starting IMMORTAL ULTIMA OMEGA v7.6 KEFKA GOD MODE — MIRACLE SHOES RELEASE"

# ─────────────────────────────────────────────────────────────────────────────
# PREFLIGHT: HARDWARE FINGERPRINT
# ─────────────────────────────────────────────────────────────────────────────
sect "Preflight: Universal Hardware Fingerprint + RAM/VM/DE/CachyOS/RAID Detection"
echo ""

IS_LAPTOP=0
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  IS_LAPTOP=1; log "Form factor: LAPTOP (battery detected)"
else
  log "Form factor: DESKTOP (no battery)"
fi

TOTAL_RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
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

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo "unknown")
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | xargs 2>/dev/null || echo "unknown")
IS_INTEL_CPU=0; IS_AMD_CPU=0; IS_RYZEN=0; IS_RYZEN9=0
if   [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then IS_INTEL_CPU=1; log "CPU: Intel — $CPU_MODEL"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
  IS_AMD_CPU=1
  echo "$CPU_MODEL" | grep -qi 'ryzen' && IS_RYZEN=1
  echo "$CPU_MODEL" | grep -qi 'ryzen 9' && IS_RYZEN9=1
  log "CPU: AMD — $CPU_MODEL (Ryzen=$IS_RYZEN Ryzen9=$IS_RYZEN9)"
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

# RAID detection
HAS_RAID=0
if command -v mdadm >/dev/null 2>&1 && grep -q '^md' /proc/mdstat 2>/dev/null; then
  HAS_RAID=1; log "MD RAID arrays detected — RAID scrub timer will be configured"
else
  info "No MD RAID arrays detected"
fi

DE="unknown"
if   pgrep -x gnome-shell >/dev/null 2>&1; then DE="GNOME"
elif pgrep -x plasmashell >/dev/null 2>&1; then DE="KDE"
elif [[ -n "${XDG_CURRENT_DESKTOP:-}" ]];  then DE="${XDG_CURRENT_DESKTOP}"; fi
log "Desktop Environment: $DE"

info ""
info "Hardware summary → CPU: ${CPU_VENDOR} | GPU: NVIDIA=$GPU_NVIDIA AMD=$GPU_AMD Intel=$GPU_INTEL"
info "                   Laptop=$IS_LAPTOP | Ryzen=$IS_RYZEN Ryzen9=$IS_RYZEN9 | CachyOS=$IS_CACHYOS ($CACHYOS_SCHED)"
info "                   scx=$HAS_SCX | RAM=${TOTAL_RAM_GB}GB | VM=$IS_VM | DE=$DE | RAID=$HAS_RAID"
info "NVMe: ${NVME_DRIVES[*]:-none} | SATA HDD: ${SATA_HDDS[*]:-none} | SATA SSD: ${SATA_SSDS[*]:-none}"

# ─────────────────────────────────────────────────────────────────────────────
step "State & Safety Setup (v7.6)"
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
  if ! { dnf copr list 2>/dev/null || dnf5 copr list 2>/dev/null || true; } | grep -q 'bieszczaders/kernel-cachyos'; then
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
  tuned tuned-ppd xclip wl-clipboard rng-tools curl
)
[[ $GPU_NVIDIA -eq 1 ]]                     && PKGS_ALL+=(akmod-nvidia xorg-x11-drv-nvidia-cuda)
[[ $GPU_AMD -eq 1 || $GPU_INTEL -eq 1 ]]    && PKGS_ALL+=(mesa-va-drivers)
[[ $IS_LAPTOP -eq 1 ]]                       && PKGS_ALL+=(power-profiles-daemon thermald)
[[ $ENABLE_NETDATA -eq 1 ]]                  && PKGS_ALL+=(netdata)
[[ $ENABLE_GAMING -eq 1 ]]                   && PKGS_ALL+=(gamemode mangohud)
[[ $ENABLE_SECURITY -eq 1 ]]                 && PKGS_ALL+=(fail2ban)

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
  if [[ "$(getenforce 2>/dev/null || echo 'Disabled')" == "Enforcing" ]]; then
    backup_file /etc/selinux/config
    if [[ $DRY_RUN -eq 0 ]]; then
      sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
      setenforce 0 2>/dev/null || true
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
# ─────────────────────────────────────────────────────────────────────────────
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
# NVIDIA — Immortal Ultima Omega v7.6 (RTX 50-series + explicit sync ready)
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
# AMD GPU — Immortal Ultima Omega v7.6
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff
AMDEOF
  log "AMD modprobe written"
elif [[ $GPU_INTEL -eq 1 ]]; then
  INTEL_CONF=/etc/modprobe.d/i915-immortal.conf
  backup_file "$INTEL_CONF"
  write_file "$INTEL_CONF" << 'INTEOF'
# Intel iGPU — Immortal Ultima Omega v7.6
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
    FREE=$(df -BG /mnt/ExtraStorage 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4}' || echo 0)
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
step "Sysctl — with CachyOS BORE/EEVDF-aware tuning (v7.6)"
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
        kernel.sched_bore)                  SYSCTL_CONTENT+=$'\n'"${knob}=1" ;;
        kernel.sched_min_base_slice_ns)     SYSCTL_CONTENT+=$'\n'"${knob}=1000000" ;;
        kernel.sched_wakeup_granularity_ns) SYSCTL_CONTENT+=$'\n'"${knob}=3000000" ;;
        kernel.sched_latency_ns)            SYSCTL_CONTENT+=$'\n'"${knob}=6000000" ;;
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
    if [[ -w /sys/power/mem_sleep ]] && grep -q deep /sys/power/mem_sleep 2>/dev/null; then
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
step "Monitor Wake & Display Recovery (Minimal Safe — v7.6 — KIO/taskbar crash fix)"
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
# Immortal Display Wake v7.6 — must be run as logged-in user, not root daemon
wake_log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a /tmp/immortal-display-wake.log; }
wake_log "Display wake triggered — minimal safe staggered (v7.6)"
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  wake_log "No DISPLAY or WAYLAND_DISPLAY — skipping (called from wrong context?)"
  exit 0
fi
for i in {1..10}; do
  [[ -e /dev/dri/renderD128 ]] && { wake_log "Render node ready"; break; }
  sleep 1
done
if [[ -n "${DISPLAY:-}" ]] && command -v xrandr &>/dev/null; then
  for out in $(xrandr 2>/dev/null | awk '/ connected/{print $1}'); do
    wake_log "Waking monitor: $out"
    xrandr --output "$out" --auto 2>/dev/null || true
    xrandr --output "$out" --set "Broadcast RGB" "Full" 2>/dev/null || true
    sleep 2.5
  done
fi
# Minimal repaint — plasmashell SIGUSR1 ONLY (no qdbus/KWin calls — prevents kioworker/taskbar crash)
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
    echo "# Immortal Ultima Omega v7.6 KEFKA GOD MODE — smartd.conf"
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
step "Core Immortality Daemons (v7.6 — enhanced Guardian with plasmashell QML revive)"
# ─────────────────────────────────────────────────────────────────────────────
[[ $GPU_NVIDIA -eq 1 ]] && enable_service nvidia-persistenced "nvidia-persistenced"
enable_service fstrim.timer "fstrim.timer (weekly TRIM)"

GUARDIAN=/usr/local/bin/immortal-guardian
write_file "$GUARDIAN" << GUARDEOF
#!/bin/bash
# Immortal Guardian v7.6 — drive lists baked in + plasmashell QML revive
EXOS_LIST="${EXOS_DRIVES[*]:-}"
NVME_LIST="${NVME_DRIVES[*]:-}"
GUARDIAN_LOG="/var/log/immortal-guardian.log"
guard_log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\$GUARDIAN_LOG" >&2; }
guard_log "Patrol started (v7.6 KEFKA GOD MODE) — ABCDE triage + Miracle Shoes active"
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
# GPU/display error recovery (existing)
if dmesg --since "30 minutes ago" 2>/dev/null | grep -qiE 'nvidia.*error|drm.*error|gpu.*hang|gpu.*reset'; then
  guard_log "⚠️ GPU/Display error in dmesg — triggering display recovery for active users"
  while IFS= read -r session; do
    [[ -z "\$session" ]] && continue
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
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}')
fi
# ── MIRACLE SHOES PROTECT: Plasmashell QML cache auto-revive (Signal 6 recovery) ──
while IFS= read -r session; do
  [[ -z "\$session" ]] && continue
  uid=\$(loginctl show-session "\$session" -p User --value 2>/dev/null || echo "")
  username=\$(id -nu "\$uid" 2>/dev/null || echo "")
  [[ -z "\$username" ]] && continue
  session_type=\$(loginctl show-session "\$session" -p Type --value 2>/dev/null || echo "")
  [[ "\$session_type" != "x11" && "\$session_type" != "wayland" ]] && continue
  # Only revive if a graphical session is active but plasmashell isn't running
  if ! pgrep -u "\$uid" -x plasmashell >/dev/null 2>&1; then
    user_home=\$(getent passwd "\$username" | cut -d: -f6 2>/dev/null || echo "/home/\$username")
    guard_log "⚠️ Plasmashell not running for \$username — clearing QML cache and reviving"
    # Clear corrupt QML/icon cache that causes Signal 6 crashes
    su -c "rm -rf '\$user_home/.cache/plasmashell' '\$user_home/.cache/plasma_engine_preview' '\$user_home/.cache/icon-cache.kcache'" "\$username" 2>/dev/null || true
    user_wayland=\$(loginctl show-session "\$session" -p WaylandDisplay --value 2>/dev/null || echo "")
    user_display=\$(loginctl show-session "\$session" -p Display --value 2>/dev/null || echo "")
    if [[ -n "\$user_wayland" ]]; then
      su -c "WAYLAND_DISPLAY='\$user_wayland' kstart plasmashell --replace >/dev/null 2>&1 &" "\$username" 2>/dev/null || true
    elif [[ -n "\$user_display" ]]; then
      su -c "DISPLAY='\$user_display' kstart plasmashell --replace >/dev/null 2>&1 &" "\$username" 2>/dev/null || true
    fi
    guard_log "Plasmashell QML revive dispatched for \$username"
  fi
done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}')
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
  # Auto-escalate to immortal-heal if drive is failing
  if echo "\$STATUS" | grep -qi 'FAILED'; then
    guard_log "🚨 DRIVE FAILURE DETECTED: \$dev — invoking immortal-heal"
    /usr/local/bin/immortal-heal "drive_failure" "\$dev" >> "\$GUARDIAN_LOG" 2>&1 || true
  fi
done
# SMART health for NVMe drives
for dev in \$NVME_LIST; do
  [[ -b "\$dev" ]] || continue
  STATUS=\$(smartctl -H "\$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print \$2}' | xargs)
  guard_log "NVMe \$dev: \${STATUS:-no response}"
  if echo "\$STATUS" | grep -qi 'FAILED'; then
    guard_log "🚨 NVME FAILURE DETECTED: \$dev — invoking immortal-heal"
    /usr/local/bin/immortal-heal "drive_failure" "\$dev" >> "\$GUARDIAN_LOG" 2>&1 || true
  fi
done
guard_log "ABCDE triage + Miracle Shoes patrol complete — v7.6 KEFKA GOD MODE"
GUARDEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$GUARDIAN" || true

GUARDIAN_SERVICE=/etc/systemd/system/immortal-guardian.service
backup_file "$GUARDIAN_SERVICE"
write_file "$GUARDIAN_SERVICE" << 'SERVICEEOF'
[Unit]
Description=Immortal Guardian — Silent Watchdog v7.6
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
log "Guardian v7.6 deployed (plasmashell QML revive + drive failure escalation)"

# ─────────────────────────────────────────────────────────────────────────────
step "DNF5 Optimization"
# ─────────────────────────────────────────────────────────────────────────────
backup_file /etc/dnf/dnf.conf
if [[ $DRY_RUN -eq 0 ]]; then
  grep -q 'max_parallel_downloads' /etc/dnf/dnf.conf 2>/dev/null || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
  grep -q 'fastestmirror'          /etc/dnf/dnf.conf 2>/dev/null || echo "fastestmirror=True"         >> /etc/dnf/dnf.conf
else
  info "[DRY-RUN] Would add max_parallel_downloads=10 and fastestmirror=True to /etc/dnf/dnf.conf"
fi
log "DNF5 optimized"

# ─────────────────────────────────────────────────────────────────────────────
step "Performance Engine: Tuned Immortal Ultima (v7.6 — correct governors)"
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
    log "Tuned profile: SCHEDUTIL governor (laptop — battery-aware)"
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
      sed -i "s/^SCX_SCHEDULER=.*/SCX_SCHEDULER=$SCX_SCHEDULER/" /etc/scx.conf 2>/dev/null \
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
step "Firefox Latency Fix (v7.6 — idempotent, no duplicate prefs)"
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

# ═════════════════════════════════════════════════════════════════════════════
# ██  MIRACLE SHOES LAYER  ██  HASTE · PROTECT · REGEN · OMNISCIENCE  ██
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
step "Miracle Shoes — HASTE (Fiber Network + Ryzen CPU Latency Tuning)"
# ─────────────────────────────────────────────────────────────────────────────
HASTE_SYSCTL=/etc/sysctl.d/99-immortal-haste.conf
backup_file "$HASTE_SYSCTL"
HASTE_CONTENT='# Immortal Ultima Omega v7.6 — Miracle Shoes HASTE
# TCP Fast Open — reduces handshake latency on fiber connections
net.ipv4.tcp_fastopen=3
# Larger connection queue for 1Gbps+ links
net.core.somaxconn=65535
net.core.netdev_max_backlog=16384
# TIME_WAIT reuse — faster connection recycling
net.ipv4.tcp_tw_reuse=1
# Fiber-optimized TCP buffer sizes (4K min / 256K default / 16M max)
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
# Increase UDP buffer for audio/DAC stability
net.core.rmem_max=16777216
net.core.wmem_max=16777216'

if [[ $IS_AMD_CPU -eq 1 && $IS_RYZEN -eq 1 ]]; then
  info "Ryzen detected — adding CPU scheduler migration cost tuning"
  HASTE_CONTENT+=$'\n# Ryzen HASTE: reduce inter-core task migration overhead'
  HASTE_CONTENT+=$'\nkernel.sched_migration_cost_ns=500000'
  if [[ $IS_RYZEN9 -eq 1 ]]; then
    info "Ryzen 9 detected — adding CCD-aware NUMA latency hint"
    HASTE_CONTENT+=$'\n# Ryzen 9 CCD tuning: encourage tasks to stay within one CCD'
    HASTE_CONTENT+=$'\nkernel.numa_balancing=1'
  fi
fi

echo "$HASTE_CONTENT" | write_file "$HASTE_SYSCTL"
if [[ $DRY_RUN -eq 0 ]]; then
  sysctl -p "$HASTE_SYSCTL" >> "$LOG_FILE" 2>&1 || true
fi
log "✅ Miracle Shoes HASTE applied — TCP FastOpen + fiber buffers + Ryzen scheduler tuning"

# ─────────────────────────────────────────────────────────────────────────────
step "Miracle Shoes — PROTECT (Weekly SMART Long Tests + Drive Health Patrol)"
# ─────────────────────────────────────────────────────────────────────────────
SMART_WEEKLY=/usr/local/bin/immortal-smart-weekly.sh
write_file "$SMART_WEEKLY" << 'SMARTEOF'
#!/bin/bash
# Immortal SMART Weekly Long Test v7.6 — Miracle Shoes PROTECT
LOG="/var/log/immortal-guardian.log"
smart_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SMART-PROTECT] $*" | tee -a "$LOG"; }
smart_log "Starting weekly SMART long test sweep"
FAIL_COUNT=0
for dev in /dev/sd[a-z] /dev/nvme[0-9]*n[0-9]; do
  [[ -b "$dev" ]] || continue
  # Skip USB devices
  transport=$(udevadm info --query=property --name="$dev" 2>/dev/null | grep '^ID_BUS=' | cut -d= -f2 || echo "")
  [[ "$transport" == "usb" ]] && { smart_log "  Skipping USB: $dev"; continue; }
  smart_log "  Queuing long test: $dev"
  if [[ "$dev" == /dev/nvme* ]]; then
    smartctl -t long "$dev" >> "$LOG" 2>&1 || smart_log "  WARNING: long test unavailable for $dev"
  else
    smartctl -d sat -t long "$dev" >> "$LOG" 2>&1 || smartctl -t long "$dev" >> "$LOG" 2>&1 || true
  fi
  # Check current health while we're here
  STATUS=$(smartctl -H "$dev" 2>/dev/null | grep -Ei 'SMART overall|Health Status' | awk -F: '{print $2}' | xargs || echo "unknown")
  smart_log "  Health $dev: ${STATUS:-unknown}"
  echo "$STATUS" | grep -qi 'FAILED' && FAIL_COUNT=$((FAIL_COUNT + 1))
done
if [[ $FAIL_COUNT -gt 0 ]]; then
  smart_log "🚨 WARNING: $FAIL_COUNT drive(s) reported FAILED health — check logs immediately"
  /usr/local/bin/immortal-heal "drive_health_weekly" "multiple" 2>/dev/null || true
fi
smart_log "Weekly SMART long test sweep complete (failures: $FAIL_COUNT)"
SMARTEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$SMART_WEEKLY" || true

write_file /etc/systemd/system/immortal-smart-weekly.service << 'SMARTSVCEOF'
[Unit]
Description=Immortal Miracle Shoes PROTECT — Weekly SMART Long Test
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-smart-weekly.sh
Nice=19
IOSchedulingClass=idle
SMARTSVCEOF

write_file /etc/systemd/system/immortal-smart-weekly.timer << 'SMARTTIMEREOF'
[Unit]
Description=Immortal Miracle Shoes PROTECT — Weekly SMART Schedule
[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true
RandomizedDelaySec=30min
[Install]
WantedBy=timers.target
SMARTTIMEREOF

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
enable_service immortal-smart-weekly.timer "Miracle Shoes PROTECT (weekly SMART)"
log "✅ Miracle Shoes PROTECT active — weekly long tests every Sunday at 3:30 AM"

# ─────────────────────────────────────────────────────────────────────────────
step "Miracle Shoes — REGEN (Monthly Auto-Cleanup + Drive Health)"
# ─────────────────────────────────────────────────────────────────────────────
REGEN_SCRIPT=/usr/local/bin/immortal-regen-monthly.sh
write_file "$REGEN_SCRIPT" << 'REGENEOF'
#!/bin/bash
# Immortal Monthly Regen v7.6 — Miracle Shoes REGEN
LOG="/var/log/immortal-guardian.log"
regen_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REGEN] $*" | tee -a "$LOG"; }
regen_log "Monthly Regen started — system self-renewal in progress"

# Journal vacuum (keep 14 days)
regen_log "Vacuuming journals older than 14 days..."
journalctl --vacuum-time=14d 2>/dev/null >> "$LOG" || true

# DNF: remove orphaned packages
regen_log "Removing orphaned DNF packages..."
dnf autoremove -y >> "$LOG" 2>&1 || true

# Flatpak: remove unused runtimes
if command -v flatpak >/dev/null 2>&1; then
  regen_log "Removing unused Flatpak runtimes..."
  flatpak uninstall --unused -y >> "$LOG" 2>&1 || true
fi

# FSTRIM all mounted filesystems
regen_log "Running fstrim on all mounted filesystems..."
fstrim -av >> "$LOG" 2>&1 || true

# Clear old thumbnail caches > 30 days
find /home -type d -name 'thumbnails' 2>/dev/null | while read -r tdir; do
  find "$tdir" -type f -atime +30 -delete 2>/dev/null || true
done
regen_log "Old thumbnail caches cleaned"

# Rotate immortal logs if > 50MB
for logfile in /var/log/immortal-*.log; do
  [[ -f "$logfile" ]] || continue
  SIZE=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
  if [[ $SIZE -gt 52428800 ]]; then
    mv "$logfile" "${logfile}.$(date +%Y%m%d).old"
    touch "$logfile"
    regen_log "Rotated large log: $logfile (${SIZE} bytes)"
  fi
done

regen_log "Monthly Regen complete — system renewed"
REGENEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$REGEN_SCRIPT" || true

write_file /etc/systemd/system/immortal-regen-monthly.service << 'REGENSVCEOF'
[Unit]
Description=Immortal Miracle Shoes REGEN — Monthly Auto-Cleanup
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-regen-monthly.sh
Nice=19
IOSchedulingClass=idle
REGENSVCEOF

write_file /etc/systemd/system/immortal-regen-monthly.timer << 'REGENTMLEOF'
[Unit]
Description=Immortal Miracle Shoes REGEN — Monthly Schedule
[Timer]
OnCalendar=monthly
Persistent=true
RandomizedDelaySec=2h
[Install]
WantedBy=timers.target
REGENTMLEOF

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
fi
enable_service immortal-regen-monthly.timer "Miracle Shoes REGEN (monthly cleanup)"
log "✅ Miracle Shoes REGEN active — monthly journal vacuum, DNF cleanup, fstrim, log rotation"

# ─────────────────────────────────────────────────────────────────────────────
step "Miracle Shoes — OMNISCIENCE (Netdata Real-Time Dashboard)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $ENABLE_NETDATA -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    if ! command -v netdata >/dev/null 2>&1; then
      info "Installing Netdata..."
      dnf install -y netdata >> "$LOG_FILE" 2>&1 || warn "Netdata install failed — check DNF repos"
    fi
    if command -v netdata >/dev/null 2>&1; then
      # Basic Netdata config: history, update interval
      NETDATA_CONF=/etc/netdata/netdata.conf
      if [[ ! -f "$NETDATA_CONF" ]]; then
        mkdir -p /etc/netdata
        cat > "$NETDATA_CONF" << 'NDEOF'
[global]
    history = 3600
    update every = 2
    memory mode = ram
[web]
    bind to = localhost
NDEOF
      fi
      enable_service netdata "Netdata real-time dashboard"
      NETDATA_URL="http://localhost:19999"
      log "✅ Miracle Shoes OMNISCIENCE active — Netdata dashboard: $NETDATA_URL"
      log "   Visible on any of your 5 monitors: open browser → $NETDATA_URL"
    else
      warn "Netdata not available — install manually: dnf install netdata"
    fi
  else
    info "[DRY-RUN] Would install Netdata and enable at http://localhost:19999"
  fi
else
  info "Netdata OMNISCIENCE skipped — re-run with --enable-netdata to activate"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "RAID Array Integrity Scrub Timer (conditional — mdadm detected)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $HAS_RAID -eq 1 ]]; then
  RAID_SCRUB=/usr/local/bin/immortal-raid-scrub.sh
  write_file "$RAID_SCRUB" << 'RAIDEOF'
#!/bin/bash
# Immortal RAID Scrub v7.6 — integrity check for all MD arrays
LOG="/var/log/immortal-guardian.log"
raid_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RAID-SCRUB] $*" | tee -a "$LOG"; }
raid_log "Starting RAID integrity scrub on all arrays"
ERRORS=0
while IFS= read -r array; do
  [[ -z "$array" ]] && continue
  dev="/dev/$array"
  raid_log "Checking array: $dev"
  echo "check" > "/sys/block/$array/md/sync_action" 2>/dev/null || \
    mdadm --action=check "$dev" 2>/dev/null || \
    { raid_log "  WARNING: could not trigger scrub on $dev"; ERRORS=$((ERRORS+1)); }
  # Wait for scrub to complete (poll for up to 4h)
  for i in $(seq 1 480); do
    ACTION=$(cat "/sys/block/$array/md/sync_action" 2>/dev/null || echo "idle")
    [[ "$ACTION" == "idle" ]] && break
    sleep 30
  done
  MISMATCH=$(cat "/sys/block/$array/md/mismatch_cnt" 2>/dev/null || echo "unknown")
  raid_log "  $dev scrub complete — mismatch_cnt: $MISMATCH"
  [[ "$MISMATCH" != "0" && "$MISMATCH" != "unknown" ]] && ERRORS=$((ERRORS+1))
done < <(cat /proc/mdstat 2>/dev/null | grep '^md' | awk '{print $1}')
if [[ $ERRORS -gt 0 ]]; then
  raid_log "🚨 RAID scrub found $ERRORS issue(s) — check logs and array health immediately"
  /usr/local/bin/immortal-heal "raid_scrub_errors" "md_arrays" 2>/dev/null || true
fi
raid_log "RAID scrub cycle complete (issues: $ERRORS)"
RAIDEOF
  [[ $DRY_RUN -eq 0 ]] && chmod +x "$RAID_SCRUB" || true

  write_file /etc/systemd/system/immortal-raid-scrub.service << 'RAIDSVCEOF'
[Unit]
Description=Immortal RAID Array Integrity Scrub
[Service]
Type=oneshot
ExecStart=/usr/local/bin/immortal-raid-scrub.sh
Nice=19
IOSchedulingClass=idle
TimeoutSec=14400
RAIDSVCEOF

  write_file /etc/systemd/system/immortal-raid-scrub.timer << 'RAIDTMLEOF'
[Unit]
Description=Immortal RAID Scrub — Monthly Schedule
[Timer]
OnCalendar=*-*-01 02:00:00
Persistent=true
RandomizedDelaySec=1h
[Install]
WantedBy=timers.target
RAIDTMLEOF

  if [[ $DRY_RUN -eq 0 ]]; then
    systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  fi
  enable_service immortal-raid-scrub.timer "RAID array integrity scrub timer"
  log "✅ RAID scrub timer active — monthly integrity check on all MD arrays"
else
  info "No MD RAID arrays detected — RAID scrub timer skipped"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Gaming Module (gamemode + mangohud + CPU governor toggle)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $ENABLE_GAMING -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    # gamemode configuration
    if command -v gamemoded >/dev/null 2>&1 || rpm -q gamemode &>/dev/null; then
      GAMEMODE_INI=/etc/gamemode.ini
      if [[ ! -f "$GAMEMODE_INI" ]]; then
        write_file "$GAMEMODE_INI" << 'GMEOF'
[general]
reaper_freq=5
desired_governor=performance
default_governor=schedutil
igpu_desiredgov=powersave
igpu_defaultgov=powersave
softrealtime=auto
renice=0
ioprio=0

[filter]
blacklist=

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
amd_performance_level=high

[custom]
start=/usr/local/bin/immortal-gaming-start
end=/usr/local/bin/immortal-gaming-stop
GMEOF
        log "gamemode.ini configured with performance governor + GPU optimisations"
      else
        info "gamemode.ini already exists — not overwriting"
      fi

      # Add real user to gamemode group
      if getent group gamemode >/dev/null 2>&1; then
        usermod -aG gamemode "$REAL_USER" 2>/dev/null || true
        log "Added $REAL_USER to gamemode group"
      fi
    else
      warn "gamemode not installed — skipping gamemode.ini"
    fi

    # Gaming start/stop hooks
    write_file /usr/local/bin/immortal-gaming-start << 'GSTARTEOF'
#!/bin/bash
# Immortal Gaming Start v7.6 — called by gamemode on game launch
echo "[$(date '+%H:%M:%S')] [GAMING] Session started" >> /tmp/immortal-gaming.log
# Switch CPU governor to performance
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo "performance" > "$gov" 2>/dev/null || true
done
# Set NVMe to performance mode (disable power saving)
echo "0" > /sys/module/nvme_core/parameters/default_ps_max_latency_us 2>/dev/null || true
echo "[$(date '+%H:%M:%S')] [GAMING] Performance mode activated" >> /tmp/immortal-gaming.log
GSTARTEOF
    chmod +x /usr/local/bin/immortal-gaming-start

    write_file /usr/local/bin/immortal-gaming-stop << 'GSTOPEOF'
#!/bin/bash
# Immortal Gaming Stop v7.6 — called by gamemode when game exits
echo "[$(date '+%H:%M:%S')] [GAMING] Session ended" >> /tmp/immortal-gaming.log
# Restore tuned profile (which manages governor)
tuned-adm profile immortal-ultima 2>/dev/null || true
echo "[$(date '+%H:%M:%S')] [GAMING] Immortal profile restored" >> /tmp/immortal-gaming.log
GSTOPEOF
    chmod +x /usr/local/bin/immortal-gaming-stop

    log "✅ Gaming Module active — gamemode + mangohud installed"
    log "   Usage: gamemoderun %command% in Steam launch options"
    log "   mangohud: MANGOHUD=1 gamemoderun %command%"
  else
    info "[DRY-RUN] Would configure gamemode, mangohud, gaming start/stop hooks"
  fi
else
  info "Gaming Module skipped — re-run with --enable-gaming to activate"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "Security Module — fail2ban (SSH brute-force protection)"
# ─────────────────────────────────────────────────────────────────────────────
if [[ $ENABLE_SECURITY -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    if command -v fail2ban-server >/dev/null 2>&1 || rpm -q fail2ban &>/dev/null; then
      JAIL_LOCAL=/etc/fail2ban/jail.local
      if [[ ! -f "$JAIL_LOCAL" ]]; then
        write_file "$JAIL_LOCAL" << 'F2BEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 7200
F2BEOF
        log "fail2ban jail.local configured (SSH: 3 retries → 2h ban)"
      else
        info "fail2ban jail.local already exists — not overwriting"
      fi
      enable_service fail2ban "fail2ban SSH protection"
      log "✅ Security Module active — fail2ban protecting SSH"
    else
      warn "fail2ban not installed — skipping (run with --skip-packages=0 and --enable-security)"
    fi
  else
    info "[DRY-RUN] Would configure fail2ban with SSH jail (3 retries → 2h ban)"
  fi
else
  info "Security Module skipped — re-run with --enable-security to activate"
fi

# ─────────────────────────────────────────────────────────────────────────────
step "immortal-heal.sh — Automated Remediation Helper (webhook-ready)"
# ─────────────────────────────────────────────────────────────────────────────
HEAL_SCRIPT=/usr/local/bin/immortal-heal
write_file "$HEAL_SCRIPT" << 'HEALEOF'
#!/bin/bash
# Immortal Heal v7.6 — conservative automated remediation + webhook alerts
# Usage: immortal-heal <event_type> <subject>
# Set IMMORTAL_WEBHOOK env var to send alerts to Matrix/Discord/Telegram/HTTP
HEAL_LOG="/var/log/immortal-heal.log"
EVENT="${1:-unknown}"
SUBJECT="${2:-unknown}"
HOSTNAME=$(hostname)
heal_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HEAL] $*" | tee -a "$HEAL_LOG"; }

send_alert() {
  local msg="$1"
  heal_log "ALERT → $msg"
  # Webhook: set IMMORTAL_WEBHOOK to your endpoint (Discord/Matrix/Telegram/custom HTTP)
  local webhook="${IMMORTAL_WEBHOOK:-}"
  if [[ -n "$webhook" ]]; then
    curl -sf -X POST \
      -H 'Content-Type: application/json' \
      --data "{\"text\":\"[IMMORTAL $HOSTNAME] $msg\"}" \
      "$webhook" >/dev/null 2>&1 || heal_log "  WARNING: webhook delivery failed"
  fi
}

heal_log "Heal invoked: event=$EVENT subject=$SUBJECT"

case "$EVENT" in
  drive_failure)
    send_alert "🚨 DRIVE FAILURE: $SUBJECT on $HOSTNAME — IMMEDIATE ATTENTION REQUIRED"
    heal_log "Drive failure on $SUBJECT — marking for review, no destructive action taken"
    # Write a flag file that immortal-status can display
    echo "DRIVE_FAILURE:$SUBJECT:$(date '+%Y-%m-%d %H:%M:%S')" >> /var/lib/immortal/failure_flags
    ;;
  drive_health_weekly)
    send_alert "⚠️ Weekly SMART check found failing drives on $HOSTNAME — check logs"
    heal_log "Weekly SMART health alert sent"
    ;;
  raid_scrub_errors)
    send_alert "⚠️ RAID scrub found mismatches on $HOSTNAME — check mdstat and array health"
    heal_log "RAID scrub alert sent"
    ;;
  service_restart)
    heal_log "Service restart event: $SUBJECT"
    systemctl restart "$SUBJECT" 2>/dev/null && \
      heal_log "  ✓ $SUBJECT restarted successfully" || \
      { heal_log "  ✗ $SUBJECT restart failed"; send_alert "Service $SUBJECT failed to restart on $HOSTNAME"; }
    ;;
  *)
    heal_log "Unknown event type: $EVENT — logged only"
    send_alert "Unknown heal event: $EVENT / $SUBJECT on $HOSTNAME"
    ;;
esac

heal_log "Heal complete: event=$EVENT subject=$SUBJECT"
HEALEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$HEAL_SCRIPT" || true
log "immortal-heal deployed — set IMMORTAL_WEBHOOK=https://your-endpoint for push alerts"

# ─────────────────────────────────────────────────────────────────────────────
step "Companion Tools — immortal-status & immortal-health-check (v7.6)"
# ─────────────────────────────────────────────────────────────────────────────
STATUS_SCRIPT=/usr/local/bin/immortal-status
write_file "$STATUS_SCRIPT" << 'STATUS_EOF'
#!/bin/bash
CYN=$'\e[0;36m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'; BOLD=$'\e[1m'
echo -e "${CYN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYN}║ IMMORTAL ULTIMA OMEGA v7.6 — MIRACLE SHOES — LIVE STATUS DASHBOARD     ║${NC}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo "Uptime   : $(uptime -p)"
echo "Kernel   : $(uname -r)"
echo "Tuned    : $(tuned-adm active 2>/dev/null | grep -o 'profile:.*' || echo 'none')"
echo "ZRAM     : $(swapon --show 2>/dev/null | grep zram || echo 'none')"
echo ""
echo -e "${BOLD}── Core Daemons ──────────────────────────────────────${NC}"
for svc in immortal-guardian.timer immortal-sentinel.service earlyoom irqbalance tuned smartd; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  [[ "$state" == "active" ]] && col="$GRN" || col="$YLW"
  printf "  %-40s %b%s%b\n" "$svc" "$col" "$state" "$NC"
done
echo ""
echo -e "${BOLD}── Miracle Shoes ─────────────────────────────────────${NC}"
for svc in immortal-smart-weekly.timer immortal-regen-monthly.timer immortal-raid-scrub.timer netdata fail2ban; do
  state=$(systemctl is-active "$svc" 2>/dev/null || echo "not-installed")
  [[ "$state" == "active" ]] && col="$GRN" || col="$YLW"
  printf "  %-40s %b%s%b\n" "$svc" "$col" "$state" "$NC"
done
echo ""
echo -e "${BOLD}── Hardware ──────────────────────────────────────────${NC}"
command -v nvidia-smi &>/dev/null && echo "  GPU Temp : $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)°C"
command -v scx_rusty  &>/dev/null && echo "  scx      : $(systemctl is-active scx 2>/dev/null)"
echo "  Swap     : $(free -h 2>/dev/null | awk '/^Swap:/{print $3 "/" $2}')"
echo ""
# Show any failure flags
if [[ -s /var/lib/immortal/failure_flags ]]; then
  echo -e "${RED}── ⚠️  Failure Flags (require attention) ───────────────${NC}"
  cat /var/lib/immortal/failure_flags | while read -r flag; do
    echo -e "  ${RED}$flag${NC}"
  done
  echo ""
fi
echo -e "${GRN}The fortress is alive and watching. Kefka approves.${NC}"
echo "  WEBHOOK: export IMMORTAL_WEBHOOK=https://your-hook  (immortal-heal sends alerts there)"
STATUS_EOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$STATUS_SCRIPT" || true

HEALTH_SCRIPT=/usr/local/bin/immortal-health-check
write_file "$HEALTH_SCRIPT" << 'HEALTH_EOF'
#!/bin/bash
echo "Running full health check (v7.6 — Miracle Shoes)..."
fwupdmgr get-updates --quiet 2>/dev/null || true
FIRST_NVME=$(nvme list 2>/dev/null | awk '/^\/dev\/nvme/{print $1; exit}')
if [[ -n "$FIRST_NVME" ]]; then
  echo "Running SMART short test on $FIRST_NVME..."
  smartctl -t short "$FIRST_NVME" 2>/dev/null || true
else
  echo "No NVMe drive found for SMART test"
fi
echo "Tuned active profile  : $(tuned-adm active 2>/dev/null || echo 'none')"
echo "SMART Protect timer   : $(systemctl is-active immortal-smart-weekly.timer 2>/dev/null)"
echo "Regen Monthly timer   : $(systemctl is-active immortal-regen-monthly.timer 2>/dev/null)"
echo "RAID Scrub timer      : $(systemctl is-active immortal-raid-scrub.timer 2>/dev/null)"
command -v fail2ban-client &>/dev/null && echo "fail2ban status       : $(fail2ban-client status 2>/dev/null | head -3)"
echo "Health check complete — see /var/log/immortal-ultima-omega.log"
HEALTH_EOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$HEALTH_SCRIPT" || true
log "Companion tools installed — run 'immortal-status' anytime"

# ─────────────────────────────────────────────────────────────────────────────
step "Easy Log Commands (v7.6)"
# ─────────────────────────────────────────────────────────────────────────────
write_file /usr/local/bin/immortal-logs << 'LOGSEOF'
#!/bin/bash
case "${1:-all}" in
  sentinel)  journalctl -u immortal-sentinel -n 100 --no-pager ;;
  guardian)  journalctl -u immortal-guardian -n 100 --no-pager ;;
  smart)     journalctl -u immortal-smart-weekly -n 100 --no-pager ;;
  regen)     journalctl -u immortal-regen-monthly -n 100 --no-pager ;;
  raid)      journalctl -u immortal-raid-scrub -n 100 --no-pager ;;
  heal)      tail -n 100 /var/log/immortal-heal.log 2>/dev/null || echo "No heal log yet" ;;
  all)       journalctl -u immortal-sentinel -u immortal-guardian -n 50 --no-pager ;;
  -f|follow) journalctl -u immortal-sentinel -f ;;
  *)         echo "Usage: immortal-logs [sentinel|guardian|smart|regen|raid|heal|all|-f]" ;;
esac
LOGSEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x /usr/local/bin/immortal-logs || true
log "Easy log commands installed — run 'immortal-logs [sentinel|guardian|smart|regen|raid|heal|all|-f]'"

# ─────────────────────────────────────────────────────────────────────────────
step "Immortal Sentinel Daemon (v7.6 — 3 AM maintenance window + Miracle Shoes Regen)"
# ─────────────────────────────────────────────────────────────────────────────
SENTINEL=/usr/local/bin/immortal-sentinel
write_file "$SENTINEL" << 'SENTINELEOF'
#!/bin/bash
# Immortal Sentinel v7.6 — system-level healing + 3 AM maintenance (no display calls)
LOG="/var/log/immortal-sentinel.log"
REGEN_DATE_FILE="/var/lib/immortal/last-sentinel-regen-date"
sentinel_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }
sentinel_log "Immortal Sentinel v7.6 started — healing + Miracle Shoes 3AM maintenance"
while true; do
  # ── Service watchdog ─────────────────────────────────────────────────────
  for svc in earlyoom irqbalance tuned smartd; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
      sentinel_log "⚠️ $svc is inactive — attempting restart"
      systemctl restart "$svc" 2>/dev/null && sentinel_log "✓ $svc restarted" \
        || { sentinel_log "✗ $svc restart failed"; /usr/local/bin/immortal-heal "service_restart" "$svc" 2>/dev/null || true; }
    fi
  done
  # ── Swap pressure relief ─────────────────────────────────────────────────
  SWAPUSED=$(free 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%.0f", $3/$2*100; else print 0}')
  if [[ "${SWAPUSED:-0}" -gt 80 ]]; then
    sentinel_log "⚠️ Swap usage at ${SWAPUSED}% — triggering swapoff/on cycle"
    swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
  fi
  # ── OOM detection ────────────────────────────────────────────────────────
  if journalctl --since "-20min" --no-pager -q 2>/dev/null | grep -q 'Out of memory'; then
    sentinel_log "⚠️ OOM event detected — logging for review"
    journalctl --since "-20min" --no-pager -q 2>/dev/null | grep 'Out of memory' | tail -5 >> "$LOG"
  fi
  # ── 3 AM Miracle Shoes Regen maintenance window ──────────────────────────
  CURRENT_HOUR=$(date +%H)
  TODAY=$(date +%Y%m%d)
  LAST_REGEN=$(cat "$REGEN_DATE_FILE" 2>/dev/null || echo "none")
  if [[ "$CURRENT_HOUR" -ge "3" && "$CURRENT_HOUR" -lt "4" && "$LAST_REGEN" != "$TODAY" ]]; then
    sentinel_log "3 AM Regen window — running inline maintenance pass"
    fstrim -av 2>/dev/null >> "$LOG" || true
    journalctl --vacuum-time=14d 2>/dev/null >> "$LOG" || true
    # Rebuild fontconfig cache to prevent KIO/thumbnail crashes
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f 2>/dev/null >> "$LOG" || true
    echo "$TODAY" > "$REGEN_DATE_FILE"
    sentinel_log "3 AM maintenance complete"
  fi
  sleep 1200
done
SENTINELEOF
[[ $DRY_RUN -eq 0 ]] && chmod +x "$SENTINEL" || true

SENTINEL_SERVICE=/etc/systemd/system/immortal-sentinel.service
write_file "$SENTINEL_SERVICE" << 'SENTINELSVCEOF'
[Unit]
Description=Immortal Sentinel Daemon (system-level healing v7.6 + Miracle Shoes)
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
log "Immortal Sentinel v7.6 deployed (3 AM maintenance window + service watchdog)"

# ─────────────────────────────────────────────────────────────────────────────
step "Kernel Hardening (v7.6)"
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
step "FINAL REPORT & SELF-REGENERATION (v7.6 KEFKA GOD MODE — MIRACLE SHOES)"
# ─────────────────────────────────────────────────────────────────────────────
verify "Tuned active";            systemctl is-active --quiet tuned                          && log "Tuned: active"           || record_failure "Tuned"
verify "Guardian timer active";   systemctl is-active --quiet immortal-guardian.timer        && log "Guardian timer: active"  || record_failure "Guardian timer"
verify "Sentinel active";         systemctl is-active --quiet immortal-sentinel.service      && log "Sentinel: active"        || true
verify "EarlyOOM active";         systemctl is-active --quiet earlyoom                       && log "EarlyOOM: active"        || true
verify "IRQBalance active";       systemctl is-active --quiet irqbalance                     && log "IRQBalance: active"      || true
verify "SMART Protect timer";     systemctl is-active --quiet immortal-smart-weekly.timer    && log "SMART Protect: active"   || record_failure "SMART Protect timer"
verify "Regen Monthly timer";     systemctl is-active --quiet immortal-regen-monthly.timer   && log "Regen Monthly: active"   || record_failure "Regen Monthly timer"
[[ $HAS_RAID -eq 1 ]]      && { verify "RAID scrub timer"; systemctl is-active --quiet immortal-raid-scrub.timer    && log "RAID Scrub: active"    || true; }
[[ $HAS_SCX -eq 1 ]]       && { verify "scx active";       systemctl is-active --quiet scx                          && log "scx: active"           || true; }
[[ $ENABLE_NETDATA -eq 1 ]] && { verify "Netdata active";  systemctl is-active --quiet netdata                       && log "Netdata: active"       || record_failure "Netdata"; }
[[ $ENABLE_SECURITY -eq 1 ]] && { verify "fail2ban active"; systemctl is-active --quiet fail2ban                    && log "fail2ban: active"      || true; }

CURRENT_DATE=$(date '+%Y-%m-%d')
if [[ $DRY_RUN -eq 0 && -w "$0" ]]; then
  sed -i "s|^# Creation Date: .*|# Creation Date: $CURRENT_DATE|" "$0" 2>/dev/null || true
fi

# Machine-readable run summary
if [[ $DRY_RUN -eq 0 ]]; then
  {
    echo "---IMMORTAL_RUN_SUMMARY---"
    echo "version=7.6"
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
    echo "is_ryzen=$IS_RYZEN"
    echo "is_ryzen9=$IS_RYZEN9"
    echo "ram_gb=$TOTAL_RAM_GB"
    echo "de=$DE"
    echo "has_raid=$HAS_RAID"
    echo "enable_netdata=$ENABLE_NETDATA"
    echo "enable_gaming=$ENABLE_GAMING"
    echo "enable_security=$ENABLE_SECURITY"
    echo "miracle_shoes=HASTE,PROTECT,REGEN,OMNISCIENCE"
    echo "---END_SUMMARY---"
  } | tee -a "$LOG_FILE" > /tmp/immortal-run-summary.txt
  log "Machine-readable run summary saved to /tmp/immortal-run-summary.txt"
fi

RUN_SUMMARY=$(tail -n 400 "$LOG_FILE" 2>/dev/null | grep -E '\[Step|\[✓ PLAN|\[↻ PLAN|\[⚡ PLAN|\[🔴 PLAN|\[✗|\[⚠' | tail -n 100)

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
Preserve 100% of original behavior and all existing features including all Miracle Shoes layers.
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
echo -e "${GRN}║ IMMORTAL ULTIMA OMEGA v7.6 — MIRACLE SHOES — KEFKA GOD MODE COMPLETE   ║${NC}"
echo -e "${GRN}║ Haste ✓  Protect ✓  Regen ✓  Omniscience $([ $ENABLE_NETDATA -eq 1 ] && echo '✓' || echo '○')  Gaming $([ $ENABLE_GAMING -eq 1 ] && echo '✓' || echo '○')  Security $([ $ENABLE_SECURITY -eq 1 ] && echo '✓' || echo '○')           ║${NC}"
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
echo ""
echo " Optional modules (not yet enabled — re-run with flags to activate):"
[[ $ENABLE_NETDATA -eq 0 ]]  && echo "   --enable-netdata   → Netdata real-time dashboard (http://localhost:19999)"
[[ $ENABLE_GAMING -eq 0 ]]   && echo "   --enable-gaming    → gamemode + mangohud + CPU governor hooks"
[[ $ENABLE_SECURITY -eq 0 ]] && echo "   --enable-security  → fail2ban SSH brute-force protection"
echo ""
echo " Set IMMORTAL_WEBHOOK=https://your-endpoint to enable push alerts via immortal-heal"
echo " The fortress has reached its Miracle Shoes Final Form. Kefka approves."
