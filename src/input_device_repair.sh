#!/bin/bash
set -u

DRY_RUN=false
ASSUME_YES=false
RESTART_BLUETOOTH=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: input_device_repair.sh [options]

  --restart-bluetooth  Also restart the Bluetooth service.
  --dry-run            Show actions without changing the Mac.
  --yes                Skip confirmation prompts.
  --output DIR         Save logs and verification output in DIR.
  -h, --help           Show help.

Run with sudo because the HID and Bluetooth services are system services.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-bluetooth) RESTART_BLUETOOTH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
[ "$(id -u)" -eq 0 ] || { echo "Run this repair with sudo." >&2; exit 3; }

TARGET_USER="${SUDO_USER:-$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo root)}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo 0)
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./input-device-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Target user: $TARGET_USER ($TARGET_UID)"
    echo
    echo "Input services:"
    ps -Ao pid,user,etime,comm,args | grep -Ei 'hidd|bluetoothd|TextInput|InputMethodKit' | grep -v grep || true
    echo
    echo "HID devices:"
    /usr/sbin/ioreg -r -c IOHIDDevice -l 2>/dev/null | head -n 500
    echo
    echo "USB and Bluetooth devices:"
    /usr/sbin/system_profiler SPUSBDataType SPBluetoothDataType 2>/dev/null | head -n 600
  } > "$VERIFY" 2>&1
}

verify
if ! confirm "Restart the macOS HID service and refresh input preference caches?"; then log "Repair cancelled by user."; exit 10; fi

run_action "Restarting the HID service" /bin/launchctl kickstart -k system/com.apple.hidd || true
if [ "$TARGET_UID" -gt 0 ] && pgrep -u "$TARGET_UID" -x cfprefsd >/dev/null 2>&1; then
  run_action "Refreshing preference caches for $TARGET_USER" /usr/bin/killall -u "$TARGET_USER" cfprefsd || true
fi
if $RESTART_BLUETOOTH; then
  if confirm "Restart Bluetooth now? Wireless input devices may disconnect briefly."; then
    run_action "Restarting the Bluetooth service" /bin/launchctl kickstart -k system/com.apple.bluetoothd || true
  fi
fi

if ! $DRY_RUN; then sleep 5; fi
verify

HIDD_OK=false
pgrep -x hidd >/dev/null 2>&1 && HIDD_OK=true
if ! $HIDD_OK; then FAILURES=$((FAILURES + 1)); log "WARNING: hidd is not running after repair."; fi

if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
