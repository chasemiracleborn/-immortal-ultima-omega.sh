#!/usr/bin/env bash
# universal-omega-v1.sh — Universal OMEGA rewrite (Fedora-focused, fleet-ready)
# - Universal (not mobile): supports Intel/AMD CPUs and Intel/AMD/NVIDIA GPUs
# - Preserve core OMEGA choices: 16GB ZRAM (zstd), DNF5 tuning, sysctl hardening
# - Adds: model-risks loader, monitor daemon, ABCDE troubleshoot, kwin recovery, boot guard
# - Safety: staging, backups, rollback, dry-run, confirm, audit logs
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Metadata
# -------------------------
PROG="universal-omega-v1.sh"
VERSION="1.0"
LOG_DIR="/var/log/universal-omega"
AUDIT_LOG="$LOG_DIR/audit.log"
mkdir -p "$LOG_DIR"

# -------------------------
# Colors & logging
# -------------------------
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; MAG='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'
log(){ echo -e "${GRN}[✓]${NC} $*" | tee -a "$AUDIT_LOG"; }
info(){ echo -e "${BLU}[→]${NC} $*" | tee -a "$AUDIT_LOG"; }
warn(){ echo -e "${YLW}[⚠]${NC} $*" | tee -a "$AUDIT_LOG"; }
err(){ echo -e "${RED}[✗]${NC} $*" | tee -a "$AUDIT_LOG"; }

# -------------------------
# Defaults & state
# -------------------------
DRY_RUN=0
CONFIRM=0
NO_BACKUP=0
SKIP_PKGS=0
MODE=""   # monitor | troubleshoot | full | modules...
BACKUP_ROOT="/root/universal-omega-backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
MANIFEST="$BACKUP_DIR/MANIFEST"
STAGE_DIR="/tmp/universal-omega-stage-$TIMESTAMP"
MODEL_RISKS_DIR="/etc/universal-omega"
MODEL_RISKS_FILE="$MODEL_RISKS_DIR/model-risks.yaml"
LM_STAGE_DIR="/var/lib/universal-omega/lm-stage"
BOOT_GUARD_DIR="/etc/universal-omega/boot-guard"
mkdir -p "$BACKUP_DIR" "$STAGE_DIR" "$MODEL_RISKS_DIR" "$LM_STAGE_DIR" "$BOOT_GUARD_DIR"

FAILURES=0
FAIL_LOG=()

trap 'on_error $LINENO' ERR
on_error(){ local ln="$1"; err "Error at line $ln — aborting. Backups (if any) are in: $BACKUP_DIR"; echo "To rollback: sudo bash $BACKUP_DIR/rollback.sh"; exit 1; }

# -------------------------
# Helpers
# -------------------------
command_exists(){ command -v "$1" >/dev/null 2>&1; }
safe_run(){ if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] $*"; else eval "$@" >> "$AUDIT_LOG" 2>&1 || warn "Command failed: $*"; fi; }
backup_file(){ local f="$1"; [[ ${NO_BACKUP:-0} -eq 1 || ${DRY_RUN:-0} -eq 1 ]] && return 0; [[ -e "$f" ]] || return 0; mkdir -p "$BACKUP_DIR$(dirname "$f")"; cp -a --preserve=mode,ownership,timestamps "$f" "$BACKUP_DIR${f}"; echo "$f" >> "$MANIFEST"; info "Backed up: $f"; }
stage_write(){ local dest="$1"; mkdir -p "$STAGE_DIR$(dirname "$dest")"; cat > "$STAGE_DIR${dest}"; }
apply_stage(){ local dest="$1"; local staged="$STAGE_DIR${dest}"; if [[ -f "$staged" ]]; then backup_file "$dest"; mv -f "$staged" "$dest"; if [[ -s "$dest" ]]; then log "Applied: $dest"; else FAILURES=$((FAILURES+1)); FAIL_LOG+=("Empty after apply: $dest"); warn "Verification failed for $dest"; fi; fi; }
write_rollback_script(){
  [[ ${DRY_RUN:-0} -eq 1 ]] && return 0
  cat > "$BACKUP_DIR/rollback.sh" <<'ROLLBACK_EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="@BACKUP_DIR@"
if [[ ! -f "$BACKUP_DIR/MANIFEST" ]]; then echo "No manifest found at $BACKUP_DIR/MANIFEST"; exit 1; fi
while IFS= read -r file; do
  src="$BACKUP_DIR${file}"
  if [[ -e "$src" ]]; then cp -a --preserve=mode,ownership,timestamps "$src" "$file" && echo "Restored: $file"; else echo "Missing backup for $file"; fi
done < "$BACKUP_DIR/MANIFEST"
echo "Rollback complete"
ROLLBACK_EOF
  sed -i "s|@BACKUP_DIR@|$BACKUP_DIR|g" "$BACKUP_DIR/rollback.sh"
  chmod +x "$BACKUP_DIR/rollback.sh"
  log "Rollback script written: $BACKUP_DIR/rollback.sh"
}

# -------------------------
# Model risk loader (simple YAML parser for our needs)
# -------------------------
load_model_risks(){
  MODEL_RISKS=()
  if [[ -f "$MODEL_RISKS_FILE" ]]; then
    # Very small YAML parsing: lines like "Model_Name:" and "  - key"
    local current=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^([A-Za-z0-9_\- ]+):[[:space:]]*$ ]]; then
        current="$(echo "${BASH_REMATCH[1]}" | tr ' ' '_' )"
      elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-zA-Z0-9_\-]+) ]]; then
        key="${BASH_REMATCH[1]}"
        MODEL_RISKS+=("${current}:${key}")
      fi
    done < "$MODEL_RISKS_FILE"
  fi
}
model_has_risk_disable(){
  # usage: model_has_risk_disable "Model_Name" "i915.enable_psr"
  local model="$1"; local key="$2"
  for e in "${MODEL_RISKS[@]:-}"; do
    if [[ "$e" == "${model}:${key}" ]]; then return 0; fi
  done
  return 1
}

# -------------------------
# Hardware detection
# -------------------------
detect_hardware(){
  info "Running hardware census"
  CPU_MODEL="$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs || true)"
  IS_INTEL=0; IS_AMD=0
  if grep -qi 'intel' /proc/cpuinfo 2>/dev/null; then IS_INTEL=1; fi
  if grep -qi 'amd' /proc/cpuinfo 2>/dev/null; then IS_AMD=1; fi

  GPU_INTEL=0; GPU_AMD=0; GPU_NVIDIA=0
  if lspci -nn | grep -i 'vga' | grep -qi 'intel'; then GPU_INTEL=1; fi
  if lspci -nn | grep -i 'vga' | grep -qi 'amd\|radeon\|vega\|navi'; then GPU_AMD=1; fi
  if lspci -nn | grep -i 'vga' | grep -qi 'nvidia'; then GPU_NVIDIA=1; fi

  NVME_COUNT=0
  shopt -s nullglob
  for dev in /dev/nvme?n1; do [[ -b "$dev" ]] || continue; NVME_COUNT=$((NVME_COUNT+1)); done
  shopt -u nullglob

  # Model string (dmidecode fallback)
  MODEL_STR="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)"
  MODEL_ID="$(echo "$MODEL_STR" | tr ' ' '_' | tr -cd '[:alnum:]_-' )"
  export IS_INTEL IS_AMD GPU_INTEL GPU_AMD GPU_NVIDIA NVME_COUNT MODEL_STR MODEL_ID
  info "Detected: CPU='${CPU_MODEL:-unknown}' model='${MODEL_STR:-unknown}' GPUs: intel=$GPU_INTEL amd=$GPU_AMD nvidia=$GPU_NVIDIA NVMe=$NVME_COUNT"
}

# -------------------------
# Kernel args helper (BLS-aware)
# -------------------------
ensure_kernel_args(){
  local ARGS="$1"
  info "Ensuring kernel args: $ARGS"
  if command_exists grubby; then
    if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] grubby --update-kernel=ALL --args=\"$ARGS\""; else backup_file /etc/default/grub; safe_run "grubby --update-kernel=ALL --args='$ARGS'"; fi
  else
    info "grubby not found; skipping grubby step"
  fi
  if [[ -d /boot/loader/entries ]]; then
    shopt -s nullglob
    for entry in /boot/loader/entries/*; do
      [[ -f "$entry" ]] || continue
      if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would append args to $entry"; else backup_file "$entry"; if grep -q '^options ' "$entry" 2>/dev/null; then sed -i "s|^options \(.*\)|options \1 $ARGS|" "$entry"; elif grep -q '^linux ' "$entry" 2>/dev/null; then sed -i "s|^linux \(.*\)|linux \1 $ARGS|" "$entry"; fi; log "Appended kernel args to $entry"; fi
    done
    shopt -u nullglob
  fi
  if command_exists grub2-mkconfig && [[ $DRY_RUN -eq 0 ]]; then
    if [[ -d /sys/firmware/efi ]]; then safe_run "grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg"; else safe_run "grub2-mkconfig -o /boot/grub2/grub.cfg"; fi
  fi
}

# -------------------------
# Harvested fleet module (ITMT, codecs, DNF, sysctl)
# -------------------------
module_harvested_fleet(){
  info "MODULE: harvested-fleet"
  # ITMT
  stage_write "/etc/sysctl.d/99-universal-omega-itmt.conf" <<'EOF'
# Universal-OMEGA — prefer P-core scheduling on hybrid Intel (ITMT)
kernel.sched_itmt_enabled = 1
EOF
  apply_stage "/etc/sysctl.d/99-universal-omega-itmt.conf"

  # Mesa freeworld swap (best-effort)
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would attempt dnf swap to mesa-va-drivers-freeworld (if available)"; else
    if command_exists dnf; then if dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld >> "$AUDIT_LOG" 2>&1; then log "mesa freeworld swap attempted"; else warn "mesa freeworld swap failed or not available"; fi; else warn "dnf not found"; fi
  fi

  # DNF5 tuning
  mkdir -p /etc/dnf/dnf.conf.d
  stage_write "/etc/dnf/dnf.conf.d/99-universal-omega-dnf.conf" <<'EOF'
# Universal-OMEGA — DNF5 parallel downloads tuning
[main]
max_parallel_downloads=10
EOF
  apply_stage "/etc/dnf/dnf.conf.d/99-universal-omega-dnf.conf"

  # Sysctl hardening
  stage_write "/etc/sysctl.d/99-universal-omega-network-hardening.conf" <<'EOF'
# Universal-OMEGA — network & kernel hardening for laptops and fleet
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
kernel.dmesg_restrict = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF
  apply_stage "/etc/sysctl.d/99-universal-omega-network-hardening.conf"
  if [[ $DRY_RUN -eq 0 ]]; then sysctl --system >> "$AUDIT_LOG" 2>&1 || warn "sysctl --system had warnings"; fi
}

# -------------------------
# Power & thermal module
# -------------------------
module_power_and_thermal(){
  info "MODULE: power-and-thermal"
  PKGS=(powertop thermald power-profiles-daemon)
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would install: ${PKGS[*]}"; else if command_exists dnf; then dnf install -y "${PKGS[@]}" >> "$AUDIT_LOG" 2>&1 || warn "Power packages install had issues"; else warn "dnf not found"; fi; fi
  if [[ $DRY_RUN -eq 0 ]]; then systemctl enable --now power-profiles-daemon.service 2>/dev/null || true; systemctl enable --now thermald.service 2>/dev/null || true; fi

  # powertop auto-tune service
  stage_write "/etc/systemd/system/universal-omega-powertop.service" <<'EOF'
[Unit]
Description=Run powertop --auto-tune at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  apply_stage "/etc/systemd/system/universal-omega-powertop.service"
  if [[ $DRY_RUN -eq 0 ]]; then systemctl daemon-reload || true; systemctl enable --now universal-omega-powertop.service || warn "Failed to enable powertop service"; fi

  # NVIDIA power_save hint (if present)
  if command_exists modinfo && modinfo nvidia >/dev/null 2>&1; then
    stage_write "/etc/modprobe.d/universal-omega-nvidia.conf" <<'EOF'
# Universal-OMEGA — NVIDIA power_save hint (do not force modeset)
options nvidia power_save=1 NVreg_DynamicPowerManagement=0x02
EOF
    apply_stage "/etc/modprobe.d/universal-omega-nvidia.conf"
  fi

  # Panel self-refresh: Intel PSR only if model not disabled
  if [[ "${IS_INTEL:-0}" -eq 1 ]]; then
    if ! model_has_risk_disable "$MODEL_ID" "i915.enable_psr"; then
      ensure_kernel_args "i915.enable_psr=1"
    else
      info "PSR disabled for model $MODEL_ID by model-risks"
    fi
  fi

  # mem_sleep_default: prefer deep if supported
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would set mem_sleep_default to deep or s2idle"; else
    if [[ -w /sys/power/mem_sleep ]]; then
      if grep -q "deep" /sys/power/mem_sleep 2>/dev/null; then echo "deep" > /sys/power/mem_sleep 2>/dev/null || true; log "Set mem_sleep_default to deep"; else echo "s2idle" > /sys/power/mem_sleep 2>/dev/null || true; log "Set mem_sleep_default to s2idle"; fi
    fi
  fi
}

# -------------------------
# ZRAM, PipeWire, OOM
# -------------------------
module_zram_and_audio(){
  info "MODULE: zram-and-audio"
  stage_write "/etc/systemd/zram-generator.conf" <<'EOF'
# Universal-OMEGA — ZRAM 16GB with zstd compression
[zram0]
zram-size = 16384
compression-algorithm = zstd
swap-priority = 100
EOF
  apply_stage "/etc/systemd/zram-generator.conf"

  # PipeWire quantum override
  stage_write "/etc/pipewire/pipewire.conf.d/99-universal-omega-audio.conf" <<'EOF'
# Universal-OMEGA — PipeWire quantum and allowed rates
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 384000 ]
    default.clock.min-quantum = 32
    default.clock.max-quantum = 1024
}
EOF
  apply_stage "/etc/pipewire/pipewire.conf.d/99-universal-omega-audio.conf"

  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would install earlyoom"; else if command_exists dnf; then dnf install -y earlyoom >> "$AUDIT_LOG" 2>&1 || warn "earlyoom install failed"; systemctl enable --now earlyoom >> "$AUDIT_LOG" 2>&1 || warn "earlyoom enable failed"; fi; fi
}

# -------------------------
# Storage (NVMe safe)
# -------------------------
module_storage_universal(){
  info "MODULE: storage (universal)"
  # Remove nvme PS0 locks
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would remove nvme PS0 lock drop-ins if present"; else
    shopt -s nullglob
    for f in /etc/modprobe.d/nvme-omega* /etc/modprobe.d/nvme*; do [[ -f "$f" ]] || continue; if grep -q 'default_ps_max_latency_us' "$f" 2>/dev/null; then backup_file "$f"; sed -i '/default_ps_max_latency_us/d' "$f"; log "Removed default_ps_max_latency_us from $f"; fi; done
    shopt -u nullglob
  fi

  # udev IO rules
  stage_write "/etc/udev/rules.d/60-universal-omega-io.rules" <<'EOF'
# Universal-OMEGA — IO scheduler rules
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme*n*", ATTR{queue/read_ahead_kb}="128"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
  apply_stage "/etc/udev/rules.d/60-universal-omega-io.rules"

  # fstab tweaks: noatime,lazytime
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would update /etc/fstab entries for ext4/btrfs/xfs to include noatime,lazytime"; else
    backup_file /etc/fstab
    if grep -qE '^\s*[^#].*\s(ext4|btrfs|xfs)\s' /etc/fstab; then awk 'BEGIN{OFS=FS=" "} /^[[:space:]]*#/ {print; next} { if ($0 ~ /(ext4|btrfs|xfs)/ && $0 !~ /noatime/) { sub("defaults","defaults,noatime,lazytime") } print }' /etc/fstab > /tmp/universal-omega-fstab.tmp && mv /tmp/universal-omega-fstab.tmp /etc/fstab; log "Updated /etc/fstab with noatime,lazytime where applicable"; fi
  fi

  if [[ $DRY_RUN -eq 0 ]]; then udevadm control --reload-rules && udevadm trigger || warn "udev reload/trigger failed"; fi
}

# -------------------------
# Monitoring & video tools
# -------------------------
install_monitoring_and_video_tools(){
  info "MODULE: monitoring & video"
  PKGS=(nvtop glances lm_sensors smartmontools nvme-cli libva-utils powertop)
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would install: ${PKGS[*]}"; else if command_exists dnf; then dnf install -y "${PKGS[@]}" >> "$AUDIT_LOG" 2>&1 || warn "Monitoring/video packages failed to install"; if command_exists sensors-detect; then yes | sensors-detect >> "$AUDIT_LOG" 2>&1 || true; systemctl enable --now lm_sensors.service 2>/dev/null || true; fi; fi; fi
}

# -------------------------
# Troubleshoot ABCDE module
# -------------------------
module_troubleshoot(){
  info "MODULE: troubleshoot (ABCDE)"
  OUTDIR="/var/log/universal-omega/troubleshoot-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$OUTDIR"
  # A: Assess
  lscpu > "$OUTDIR/lscpu.txt" 2>/dev/null || true
  lsblk -o NAME,MODEL,SERIAL,ROTA > "$OUTDIR/lsblk.txt" 2>/dev/null || true
  uname -a > "$OUTDIR/uname.txt" 2>/dev/null || true
  cat /proc/cmdline > "$OUTDIR/proc-cmdline.txt" 2>/dev/null || true
  zramctl > "$OUTDIR/zramctl.txt" 2>/dev/null || true
  swapon --show > "$OUTDIR/swapon.txt" 2>/dev/null || true

  # B: Baseline
  dmesg -T > "$OUTDIR/dmesg.txt" 2>/dev/null || true
  journalctl -b -p err..emerg --no-pager > "$OUTDIR/journal-errors.txt" 2>/dev/null || true
  if command_exists smartctl; then shopt -s nullglob; for dev in /dev/nvme?n1 /dev/sd[a-z]; do [[ -b "$dev" ]] || continue; smartctl -a "$dev" > "$OUTDIR/$(basename $dev)-smartctl.txt" 2>/dev/null || true; done; shopt -u nullglob; fi

  # C: Collect
  if command_exists nvidia-smi; then nvidia-smi -q > "$OUTDIR/nvidia-smi.txt" 2>/dev/null || true; fi
  if command_exists pactl; then pactl list > "$OUTDIR/pactl-list.txt" 2>/dev/null || true; fi
  if command_exists nvme; then nvme list > "$OUTDIR/nvme-list.txt" 2>/dev/null || true; fi

  # D: Diagnose (simple heuristics)
  echo "Diagnosis summary" > "$OUTDIR/diagnosis.txt"
  if grep -qi 'drm\|nvidia\|gpu' "$OUTDIR/dmesg.txt" 2>/dev/null; then echo "Possible DRM/NVIDIA messages found; inspect dmesg excerpt" >> "$OUTDIR/diagnosis.txt"; grep -iE 'nvidia|drm|gpu' "$OUTDIR/dmesg.txt" | tail -n 50 >> "$OUTDIR/diagnosis.txt"; else echo "No obvious DRM/NVIDIA errors in dmesg" >> "$OUTDIR/diagnosis.txt"; fi

  # E: Execute (safe suggestions only)
  echo "Remediation suggestions" > "$OUTDIR/remediations.txt"
  echo "  - Backup and remove ~/.config/kwinoutputconfig.json if black-on-unlock occurs" >> "$OUTDIR/remediations.txt"
  echo "  - Restart kwin_wayland: killall -9 kwin_wayland && DISPLAY=:0 dbus-launch kwin_wayland --replace &" >> "$OUTDIR/remediations.txt"
  echo "  - Run powertop --auto-tune on AC if battery issues" >> "$OUTDIR/remediations.txt"

  # Pack support bundle
  tar -C / -czf "$OUTDIR/universal-omega-support-bundle.tgz" -T <(find "$OUTDIR" -type f -printf "%p\n") 2>/dev/null || true
  log "Troubleshoot bundle created: $OUTDIR/universal-omega-support-bundle.tgz"
  echo "$OUTDIR"
}

# -------------------------
# KWin recovery helper (per-user)
# -------------------------
install_kwin_recover(){
  local target="/usr/local/bin/universal-omega-kwin-recover.sh"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR="${HOME:-/root}/.local/share/universal-omega"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/kwin-recover.log"
echo "$(date -Is) START" >> "$LOG"
KWINCFG="$HOME/.config/kwinoutputconfig.json"
if [[ -f "$KWINCFG" ]]; then bak="$KWINCFG.mobile-omega-bak-$(date +%s)"; cp -a "$KWINCFG" "$bak"; mv "$KWINCFG" "${KWINCFG}.disabled" || true; echo "$(date -Is) Disabled $KWINCFG" >> "$LOG"; fi
pkill -TERM kwin_wayland || true; sleep 2
if [[ -n "${DISPLAY:-}" ]]; then dbus-launch kwin_wayland --replace >> "$LOG" 2>&1 || echo "$(date -Is) kwin restart failed" >> "$LOG"; fi
systemctl --user restart plasma-powerdevil.service >> "$LOG" 2>&1 || true
systemctl --user restart pipewire pipewire-pulse >> "$LOG" 2>&1 || true
if command -v chvt >/dev/null 2>&1; then chvt 3 || true; sleep 1; chvt 2 || true; fi
dmesg | tail -n 200 >> "$LOG" 2>&1 || true
journalctl -b -n 200 --no-pager >> "$LOG" 2>&1 || true
echo "$(date -Is) DONE" >> "$LOG"
echo "Recovery log: $LOG"
EOF
  chmod +x "$target"
  log "Installed kwin recovery helper: $target"
}

# -------------------------
# Monitor daemon (observe-only)
# -------------------------
install_monitor_daemon(){
  local svc="/etc/systemd/system/universal-omega-monitor.service"
  local bin="/usr/local/bin/universal-omega-monitor"
  cat > "$bin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="/var/log/universal-omega"
MON_DIR="$LOG_DIR/monitor"
STAGE_DIR="/var/lib/universal-omega/stage"
mkdir -p "$MON_DIR" "$STAGE_DIR" "$LOG_DIR"
INTERVAL_HEALTH=60
INTERVAL_DEEP=3600
while true; do
  ts=$(date +%s)
  out="$MON_DIR/quick_$(date +%Y%m%d_%H%M%S).tgz"
  tmpdir=$(mktemp -d)
  uname -a > "$tmpdir/uname.txt" || true
  cat /proc/cmdline > "$tmpdir/proc-cmdline.txt" || true
  zramctl > "$tmpdir/zramctl.txt" 2>/dev/null || true
  tar -C "$tmpdir" -czf "$out" . || true
  rm -rf "$tmpdir"
  sleep "$INTERVAL_HEALTH"
done
EOF
  chmod +x "$bin"
  cat > "$svc" <<EOF
[Unit]
Description=Universal-Omega Monitor (observe-only)
After=network.target

[Service]
Type=simple
ExecStart=$bin
Restart=on-failure
RestartSec=10
CPUQuota=20%
MemoryMax=256M
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload || true
  log "Installed monitor daemon and service"
}

# -------------------------
# Boot guard installer
# -------------------------
install_boot_guard(){
  mkdir -p "$BOOT_GUARD_DIR"
  cat > "$BOOT_GUARD_DIR/checks.sh" <<'EOF'
#!/usr/bin/env bash
# Simple boot checks: zram active, no drm/kwin errors in journal, kwin running
set -euo pipefail
if ! zramctl >/dev/null 2>&1; then echo "ZRAM missing"; exit 1; fi
if journalctl -b -p err..emerg | grep -iE 'drm|kwin|nvidia' >/dev/null 2>&1; then echo "DRM/KWIN errors"; exit 2; fi
if ! pgrep -x kwin_wayland >/dev/null 2>&1; then echo "kwin not running"; exit 3; fi
exit 0
EOF
  chmod +x "$BOOT_GUARD_DIR/checks.sh"
  cat > "$BOOT_GUARD_DIR/boot-guard.service" <<'EOF'
[Unit]
Description=Universal-Omega Boot Guard
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/universal-omega/boot-guard/checks.sh || /bin/bash -c 'logger -t UNIVERSAL-OMEGA "Boot guard failed; running rollback"; bash /root/universal-omega-backups/latest/rollback.sh || true'
RemainAfterExit=yes
EOF
  # Timer to run once after boot
  cat > "$BOOT_GUARD_DIR/boot-guard.timer" <<'EOF'
[Unit]
Description=Run Universal-Omega Boot Guard once after boot

[Timer]
OnBootSec=60
Unit=boot-guard.service

[Install]
WantedBy=timers.target
EOF
  # Install unit files
  cp "$BOOT_GUARD_DIR/boot-guard.service" /etc/systemd/system/ || true
  cp "$BOOT_GUARD_DIR/boot-guard.timer" /etc/systemd/system/ || true
  systemctl daemon-reload || true
  systemctl enable --now boot-guard.timer || warn "Failed to enable boot-guard.timer"
  log "Boot guard installed and enabled"
}

# -------------------------
# LM hooks (staging + audit only)
# -------------------------
lm_stage_suggestion(){
  # write suggestion diff to LM stage dir and audit
  local name="$1"; shift
  mkdir -p "$LM_STAGE_DIR"
  echo "$*" > "$LM_STAGE_DIR/$name.suggestion"
  sha256sum "$LM_STAGE_DIR/$name.suggestion" >> "$AUDIT_LOG"
  log "LM suggestion staged: $LM_STAGE_DIR/$name.suggestion"
}

# -------------------------
# Usage & argument parsing
# -------------------------
usage(){
  cat <<EOF
Usage: sudo bash $PROG [OPTIONS]
Options:
  --full                run all modules (harvested-fleet, power, zram, storage, monitoring)
  --harvest             run harvested-fleet module only
  --power               run power & thermal module only
  --zram                run zram & audio module only
  --storage             run storage module only
  --monitor             install monitor & video tools only
  --troubleshoot        run ABCDE troubleshoot and create support bundle
  --install-kwin-recover install kwin recovery helper
  --install-monitor     install monitor daemon
  --install-boot-guard  install boot guard
  --lm-stage "name" "text"  stage an LM suggestion (audit only)
  --dry-run             show actions without applying
  --confirm             apply without interactive prompt
  --no-backup           do not create backups (not recommended)
  --skip-packages       skip early package install
  --help
EOF
  exit 0
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) MODE="full"; shift ;;
    --harvest) MODE="harvest"; shift ;;
    --power) MODE="power"; shift ;;
    --zram) MODE="zram"; shift ;;
    --storage) MODE="storage"; shift ;;
    --monitor) MODE="monitor"; shift ;;
    --troubleshoot) MODE="troubleshoot"; shift ;;
    --install-kwin-recover) MODE="install-kwin-recover"; shift ;;
    --install-monitor) MODE="install-monitor"; shift ;;
    --install-boot-guard) MODE="install-boot-guard"; shift ;;
    --lm-stage) shift; NAME="$1"; shift; TEXT="$1"; shift; lm_stage_suggestion "$NAME" "$TEXT"; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --skip-packages) SKIP_PKGS=1; shift ;;
    --help|-h) usage ;;
    *) err "Unknown arg: $1"; usage ;;
  esac
done

# -------------------------
# Early package install
# -------------------------
if [[ $SKIP_PKGS -eq 0 ]]; then
  info "Installing essential packages (early)"
  PKGS=(smartmontools nvme-cli pciutils usbutils zram-generator pipewire pipewire-utils)
  if [[ $DRY_RUN -eq 1 ]]; then info "[DRY-RUN] Would install: ${PKGS[*]}"; else if command_exists dnf; then dnf install -y "${PKGS[@]}" >> "$AUDIT_LOG" 2>&1 || warn "DNF install had issues"; else warn "dnf not found"; fi; fi
else info "Skipping early package install (--skip-packages)"; fi

# -------------------------
# Load model risks and detect hardware
# -------------------------
load_model_risks
detect_hardware

# Confirm unless dry-run or confirm
if [[ ${DRY_RUN:-0} -eq 0 && ${CONFIRM:-0} -eq 0 && "$MODE" != "troubleshoot" && "$MODE" != "install-kwin-recover" && "$MODE" != "install-monitor" && "$MODE" != "install-boot-guard" ]]; then
  echo ""
  echo "Universal-Omega will stage changes and create backups at: $BACKUP_DIR"
  read -r -p "Type 'yes' to proceed and apply changes (or Ctrl-C to abort): " yn
  if [[ "$yn" != "yes" ]]; then info "Aborted by user"; exit 0; fi
fi

# -------------------------
# Run requested modules
# -------------------------
case "$MODE" in
  full)
    module_harvested_fleet
    module_power_and_thermal
    module_zram_and_audio
    module_storage_universal
    install_monitoring_and_video_tools
    ;;
  harvest) module_harvested_fleet ;;
  power) module_power_and_thermal ;;
  zram) module_zram_and_audio ;;
  storage) module_storage_universal ;;
  monitor) install_monitoring_and_video_tools ;;
  troubleshoot) module_troubleshoot ;;
  install-kwin-recover) install_kwin_recover ;;
  install-monitor) install_monitor_daemon ;;
  install-boot-guard) install_boot_guard ;;
  "") usage ;;
  *) err "Unknown mode: $MODE"; usage ;;
esac

# Finalize backups & rollback
if [[ ${NO_BACKUP:-0} -eq 0 && ${DRY_RUN:-0} -eq 0 ]]; then
  write_rollback_script
  if [[ -f "$MANIFEST" ]]; then tar -C / -cf "$BACKUP_DIR/backup_files.tar" -T "$MANIFEST" 2>/dev/null || true; if [[ -f "$BACKUP_DIR/backup_files.tar" ]]; then sha256sum "$BACKUP_DIR/backup_files.tar" > "$BACKUP_DIR/backup_files.tar.sha256"; log "Created backup archive and checksum"; fi; fi
else info "[NO_BACKUP or DRY-RUN] Rollback script not written"; fi

# Cleanup
if [[ -d "$STAGE_DIR" ]]; then rm -rf "$STAGE_DIR"; fi

# Final report
if [[ $FAILURES -eq 0 ]]; then echo -e "${GRN}[✓] Universal-Omega v1 completed${NC}"; else echo -e "${YLW}[⚠] Completed with $FAILURES warnings/errors${NC}"; for f in "${FAIL_LOG[@]}"; do echo "  • $f"; done; fi
echo ""
echo "Backups and rollback script (if created): $BACKUP_DIR"
echo "Audit log: $AUDIT_LOG"
echo ""
echo "Post-run recommendations:"
echo "  1) Reboot and verify: cat /proc/cmdline; zramctl; systemctl status universal-omega-powertop.service"
echo "  2) If you see black-on-unlock, run: /usr/local/bin/universal-omega-kwin-recover.sh (installed by --install-kwin-recover)"
echo "  3) Use --troubleshoot to create a support bundle for triage"
echo ""
exit 0
