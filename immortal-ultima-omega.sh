#!/usr/bin/env bash
# immortal-ultima-omega.sh
# Ultimate resilient system tuning and device helper for Fedora/DNF systems
# Creation Date: 2026-04-03
# Author: chasemiracleborn (updated)
# License: AGPL-3.0-or-later
#
# Purpose:
#   A comprehensive system tuning and device management script intended to:
#     - discover block devices safely
#     - apply kernel/sysctl tuning
#     - manage dracut/grub/kernel args safely
#     - optionally adjust SELinux (opt-in)
#     - install drivers/firmware where appropriate
#     - provide diagnostics and safe rollback helpers
#
# Design goals for this updated version:
#   - Preserve original behavior and features while improving safety, robustness,
#     and maintainability.
#   - Use safe temporary files, traps, and locking to avoid concurrent runs.
#   - Use portable, predictable shell constructs and avoid unsafe expansions.
#   - Require explicit confirmation for destructive or security-impacting changes.
#   - Provide dry-run mode and verbose logging.
#
# NOTE: This script makes system-level changes. Read it before running.
#       Use --dry-run to preview actions. Use --yes to run non-interactively.
#
# Usage:
#   sudo ./immortal-ultima-omega.sh [--dry-run] [--yes] [--verbose] [--help]
#
set -o errexit
set -o nounset
set -o pipefail

# -------------------------
# Configuration and Globals
# -------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/immortal-ultima-omega.log"
LOCK_FILE="/var/lock/immortal-ultima-omega.lock"
DRY_RUN=1
CONFIRMED=0
VERBOSE=0
FORCE=0
QUIET=0

# Colors (if terminal supports)
if [[ -t 1 ]]; then
  RED="$(printf '\033[0;31m')"
  GRN="$(printf '\033[0;32m')"
  YEL="$(printf '\033[0;33m')"
  BLU="$(printf '\033[0;34m')"
  MAG="$(printf '\033[0;35m')"
  CYN="$(printf '\033[0;36m')"
  NC="$(printf '\033[0m')"
else
  RED='' GRN='' YEL='' BLU='' MAG='' CYN='' NC=''
fi

# -------------------------
# Utility functions
# -------------------------
log() {
  local msg="$*"
  # Always write to syslog and logfile; in dry-run we still log intent
  printf '%s\n' "[$(date --iso-8601=seconds)] ${msg}" >>"$LOG_FILE" 2>/dev/null || true
  logger -t "$SCRIPT_NAME" -- "$msg" || true
  if [[ $QUIET -eq 0 ]]; then
    printf '%b\n' "${GRN}[IMMORTAL]${NC} ${msg}"
  fi
}

info() {
  [[ $VERBOSE -eq 1 ]] && printf '%b\n' "${BLU}[INFO]${NC} $*"
  log "[INFO] $*"
}

warn() {
  printf '%b\n' "${YEL}[WARN]${NC} $*"
  log "[WARN] $*"
}

err() {
  printf '%b\n' "${RED}[ERROR]${NC} $*" >&2
  log "[ERROR] $*"
}

die() {
  err "$*"
  exit 1
}

# Safe run wrapper: prints what would be done in dry-run
run_cmd() {
  if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY-RUN: $*"
    return 0
  fi
  info "RUN: $*"
  eval "$@"
}

# Write file safely (atomic)
write_file_atomic() {
  local dest="$1"
  local tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  cat >"$tmp"
  run_cmd "mv -- \"$tmp\" \"$dest\""
  run_cmd "chmod 0644 \"$dest\""
}

# Backup a file if it exists
backup_file() {
  local file="$1"
  if [[ -e "$file" ]]; then
    local bak="${file}.bak.$(date +%Y%m%d%H%M%S)"
    run_cmd "cp -a -- \"$file\" \"$bak\""
    info "Backed up $file -> $bak"
  fi
}

# Ensure we have root privileges for operations that require it
require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root. Use sudo."
  fi
}

# Acquire exclusive lock to prevent concurrent runs
acquire_lock() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    die "Another instance of $SCRIPT_NAME is running (lock: $LOCK_FILE)."
  fi
  # Keep lock until script exits
}

# Cleanup handler
cleanup() {
  local rc=$?
  # Remove any temporary files created by mktemp (trap will handle)
  # Release lock by closing fd 200
  if [[ -n "${LOCK_FILE:-}" ]]; then
    # closing fd 200 will release flock
    exec 200>&-
  fi
  if [[ $rc -ne 0 ]]; then
    err "Script exited with status $rc"
  else
    info "Script completed successfully"
  fi
  exit $rc
}
trap cleanup EXIT

# -------------------------
# Argument parsing
# -------------------------
print_help() {
  cat <<'EOF'
Usage: immortal-ultima-omega.sh [options]

Options:
  --dry-run        Show actions without making changes (default)
  --yes            Non-interactive: accept prompts and apply changes
  --verbose        Verbose output
  --quiet          Minimal console output (still logs)
  --force          Force operations where applicable
  --help           Show this help and exit

Examples:
  sudo ./immortal-ultima-omega.sh --dry-run
  sudo ./immortal-ultima-omega.sh --yes --verbose
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) CONFIRMED=1; DRY_RUN=0; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --force) FORCE=1; shift ;;
    --help|-h) print_help; exit 0 ;;
    *) warn "Unknown option: $1"; print_help; exit 2 ;;
  esac
done

# -------------------------
# Safety checks and startup
# -------------------------
# Ensure log file exists and is writable (or can be created)
if [[ ! -e "$LOG_FILE" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    touch "$LOG_FILE" 2>/dev/null || warn "Could not create log file $LOG_FILE; continuing"
  fi
fi

# Acquire lock to prevent concurrent runs
acquire_lock

# Ensure root for operations that require it
require_root

# If not confirmed and not dry-run, prompt interactively
if [[ $DRY_RUN -eq 0 && $CONFIRMED -eq 0 ]]; then
  printf '%b\n' "${YEL}WARNING:${NC} This script will make system-level changes."
  read -r -p "Type YES to proceed: " ans
  if [[ "$ans" != "YES" ]]; then
    die "User aborted."
  fi
fi

# -------------------------
# Device discovery (safe)
# -------------------------
# Build arrays of block devices using lsblk to avoid fragile globbing
discover_block_devices() {
  local -a lines
  mapfile -t lines < <(lsblk -dn -o NAME,TYPE 2>/dev/null || true)
  NVME_DRIVES=()
  SATA_DRIVES=()
  ALL_DISKS=()
  for line in "${lines[@]}"; do
    # line format: "sda disk" or "nvme0n1 disk"
    local name type
    name="${line%% *}"
    type="${line##* }"
    if [[ "$type" != "disk" ]]; then
      continue
    fi
    local dev="/dev/${name}"
    ALL_DISKS+=("$dev")
    if [[ "$name" == nvme* ]]; then
      NVME_DRIVES+=("$dev")
    else
      SATA_DRIVES+=("$dev")
    fi
  done
  info "Discovered disks: ${ALL_DISKS[*]:-none}"
  info "NVMe: ${NVME_DRIVES[*]:-none}"
  info "SATA: ${SATA_DRIVES[*]:-none}"
}

# -------------------------
# Sysctl and kernel tuning
# -------------------------
generate_sysctl_content() {
  cat <<'SYSCTL'
# Immortal Ultima Omega tuning
# net tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
# file handles
fs.file-max=2097152
# swappiness
vm.swappiness=10
SYSCTL
}

apply_sysctl() {
  local sysctl_file="/etc/sysctl.d/99-immortal-ultima-omega.conf"
  info "Preparing sysctl file: $sysctl_file"
  if [[ $DRY_RUN -eq 1 ]]; then
    generate_sysctl_content | sed -n '1,200p'
    info "DRY-RUN: Would write sysctl to $sysctl_file and run sysctl --system"
    return 0
  fi
  backup_file "$sysctl_file"
  generate_sysctl_content | write_file_atomic "$sysctl_file"
  run_cmd "sysctl --system"
  info "Applied sysctl settings from $sysctl_file"
}

# -------------------------
# GRUB and dracut management
# -------------------------
# Safely update GRUB kernel args (append only, backup first)
update_grub_cmdline() {
  local add_args="$*"
  local grub_cfg="/etc/default/grub"
  info "Will append kernel args: $add_args"
  if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY-RUN: Would backup $grub_cfg and append args to GRUB_CMDLINE_LINUX"
    return 0
  fi
  backup_file "$grub_cfg"
  # Use sed to append args if not present
  if grep -q "GRUB_CMDLINE_LINUX" "$grub_cfg"; then
    # Escape slashes for sed
    local esc_args
    esc_args="$(printf '%s' "$add_args" | sed 's/[\/&]/\\&/g')"
    # Append only if not already present
    if ! grep -q "$esc_args" "$grub_cfg"; then
      sed -i "s/^\(GRUB_CMDLINE_LINUX=.*\)\"$/\1 $add_args\"/" "$grub_cfg"
      info "Appended args to GRUB_CMDLINE_LINUX in $grub_cfg"
    else
      info "GRUB already contains the requested args"
    fi
  else
    warn "GRUB_CMDLINE_LINUX not found in $grub_cfg; skipping"
  fi
  run_cmd "grub2-mkconfig -o /boot/grub2/grub.cfg || grub-mkconfig -o /boot/grub/grub.cfg"
  info "Regenerated grub config"
}

rebuild_dracut() {
  info "Rebuilding initramfs with dracut"
  if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY-RUN: Would run dracut to rebuild initramfs for current kernel"
    return 0
  fi
  local kernel
  kernel="$(uname -r)"
  run_cmd "dracut --force --kver \"$kernel\""
  info "Dracut rebuild complete for kernel $kernel"
}

# -------------------------
# SELinux handling (opt-in)
# -------------------------
set_selinux_permissive() {
  # This is a security-sensitive operation. Only do it if CONFIRMED or FORCE.
  if [[ "$(command -v getenforce 2>/dev/null || true)" == "" ]]; then
    warn "SELinux tools not found; skipping SELinux handling"
    return 0
  fi
  local cur
  cur="$(getenforce 2>/dev/null || echo Disabled)"
  info "Current SELinux mode: $cur"
  if [[ "$cur" == "Enforcing" ]]; then
    warn "Changing SELinux to permissive reduces system security."
    if [[ $CONFIRMED -eq 1 || $FORCE -eq 1 ]]; then
      backup_file /etc/selinux/config
      if [[ $DRY_RUN -eq 1 ]]; then
        info "DRY-RUN: Would set SELINUX=permissive in /etc/selinux/config and run setenforce 0"
      else
        sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
        setenforce 0 || warn "setenforce failed; SELinux may remain enforcing"
        info "SELinux set to permissive (on-disk config updated)"
      fi
    else
      warn "Not changing SELinux because --yes/--force not provided"
    fi
  else
    info "SELinux not enforcing; no change required"
  fi
}

# -------------------------
# Driver/firmware installation (placeholder safe operations)
# -------------------------
install_drivers() {
  # This function preserves original behavior: attempt to install recommended drivers/firmware
  # but only when CONFIRMED or in dry-run show actions.
  info "Driver/firmware installation step (safe mode)"
  if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY-RUN: Would detect hardware and install recommended packages (e.g., firmware, drivers)"
    return 0
  fi
  if [[ $CONFIRMED -eq 0 && $FORCE -eq 0 ]]; then
    warn "Driver installation skipped: require --yes or --force to proceed"
    return 0
  fi
  # Example: install common firmware packages on Fedora
  if command -v dnf >/dev/null 2>&1; then
    run_cmd "dnf -y install linux-firmware"
    info "Installed linux-firmware via dnf"
  elif command -v apt-get >/dev/null 2>&1; then
    run_cmd "apt-get update && apt-get -y install linux-firmware"
    info "Installed linux-firmware via apt"
  else
    warn "No supported package manager found; skipping driver install"
  fi
}

# -------------------------
# Diagnostics and reporting
# -------------------------
run_diagnostics() {
  info "Collecting system diagnostics (safe)"
  local out
  out="$(mktemp /tmp/immortal.diag.XXXXXX)"
  trap 'rm -f "$out"' RETURN
  {
    printf '=== uname -a ===\n'
    uname -a
    printf '\n=== lsblk -a ===\n'
    lsblk -a
    printf '\n=== lspci -nnk ===\n'
    lspci -nnk || true
    printf '\n=== dmesg tail ===\n'
    dmesg | tail -n 200 || true
    printf '\n=== rpm -qa (if available) ===\n'
    if command -v rpm >/dev/null 2>&1; then rpm -qa | head -n 200; fi
  } >"$out" 2>&1
  if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY-RUN: Diagnostics collected to $out (not persisted)"
    sed -n '1,200p' "$out"
  else
    local dest="/var/log/immortal-ultima-omega.diag.$(date +%Y%m%d%H%M%S).log"
    run_cmd "mv -- \"$out\" \"$dest\""
    info "Diagnostics saved to $dest"
  fi
}

# -------------------------
# Main orchestration
# -------------------------
main() {
  info "Starting Immortal Ultima Omega (safe mode: DRY_RUN=$DRY_RUN)"
  discover_block_devices

  # Preserve original behavior: apply sysctl tuning, update grub/dracut, optionally SELinux, drivers
  apply_sysctl

  # Example kernel args to add (preserve original script's intent)
  local kernel_args="intel_iommu=on iommu=pt"
  update_grub_cmdline "$kernel_args"

  # Rebuild dracut/initramfs if requested (preserve original behavior)
  rebuild_dracut

  # SELinux handling (opt-in)
  set_selinux_permissive

  # Driver installation (safe)
  install_drivers

  # Diagnostics
  run_diagnostics

  info "All requested operations completed (DRY_RUN=$DRY_RUN). Review logs at $LOG_FILE"
}

# Run main
main "$@"
