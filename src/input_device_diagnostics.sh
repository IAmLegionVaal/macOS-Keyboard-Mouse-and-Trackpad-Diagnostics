#!/bin/bash
set -u

HOURS=24
OUTPUT_DIR=""
REPAIR=false
DRY_RUN=false
ASSUME_YES=false
RESTART_BLUETOOTH=false

usage() {
  cat <<'EOF'
Usage: input_device_diagnostics.sh [options]

  --hours N            Log lookback in hours (default: 24)
  --output DIR         Report directory
  --repair             Restart the HID service and refresh preference caches
  --restart-bluetooth  Also restart bluetoothd (temporarily disconnects devices)
  --dry-run            Show repair commands without executing them
  --yes                Skip confirmation
  -h, --help           Show help

Exit codes: 0 healthy/success, 10 attention required, 20 repair failed,
            2 invalid arguments, 3 platform/privilege error.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --repair) REPAIR=true; shift ;;
    --restart-bluetooth) REPAIR=true; RESTART_BLUETOOTH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
if $REPAIR && [ "$(id -u)" -ne 0 ]; then echo "Repair mode requires sudo." >&2; exit 3; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./input-device-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/input-device-report.txt"
CSV="$OUTPUT_DIR/devices.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
ACTION_LOG="$OUTPUT_DIR/repair-actions.log"
BACKUP_DIR="$OUTPUT_DIR/pre-repair-backup"
: > "$REPORT"; : > "$ERRORS"; : > "$ACTION_LOG"
echo 'source,name,vendor_id,product_id,transport' > "$CSV"

section() { title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
safe_csv() { printf '%s' "$1" | sed 's/"/""/g'; }
log_action() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$ACTION_LOG"; }
run_action() {
  description="$1"; shift
  if $DRY_RUN; then log_action "DRY-RUN: $description :: $*"; return 0; fi
  log_action "RUN: $description :: $*"
  if "$@" >> "$ACTION_LOG" 2>&1; then log_action "OK: $description"; return 0; fi
  log_action "FAILED: $description"; return 1
}
confirm_repair() {
  $ASSUME_YES && return 0
  printf 'Apply input-service repairs? [y/N] '
  read answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) echo "Repair cancelled."; exit 10 ;; esac
}

collect() {
  section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
  section "USB device inventory" /usr/sbin/system_profiler SPUSBDataType
  section "Bluetooth device inventory" /usr/sbin/system_profiler SPBluetoothDataType
  section "IOHID device inventory" /usr/sbin/ioreg -r -c IOHIDDevice -l
  section "Input sources" /bin/bash -c 'defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null || true; defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null || true'
  section "Keyboard preferences" /bin/bash -c 'defaults read -g InitialKeyRepeat 2>/dev/null || true; defaults read -g KeyRepeat 2>/dev/null || true; defaults read -g ApplePressAndHoldEnabled 2>/dev/null || true'
  section "Mouse and trackpad preferences" /bin/bash -c 'defaults read -g com.apple.mouse.scaling 2>/dev/null || true; defaults read -g com.apple.trackpad.scaling 2>/dev/null || true; defaults read com.apple.AppleMultitouchTrackpad 2>/dev/null || true'
  section "Accessibility input settings" /bin/bash -c 'defaults read com.apple.universalaccess 2>/dev/null | grep -Ei "sticky|slow|mouse|trackpad|keyboard" || true'
  section "Input-related processes" /bin/bash -c 'ps -Ao pid,user,etime,comm,args | grep -Ei "hidd|bluetoothd|WindowServer|TextInput|InputMethodKit" | grep -v grep || true'
  section "Recent input-device events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process == \"hidd\") OR (process == \"bluetoothd\") OR (subsystem CONTAINS[c] \"HID\") OR (eventMessage CONTAINS[c] \"keyboard\") OR (eventMessage CONTAINS[c] \"mouse\") OR (eventMessage CONTAINS[c] \"trackpad\")' 2>/dev/null | tail -n 4000"
}

collect
/usr/sbin/ioreg -r -c IOHIDDevice -l 2>/dev/null | awk -F' = ' '
  /"Product" =/ {name=$2; gsub(/^"|"$/,"",name)}
  /"VendorID" =/ {vendor=$2}
  /"ProductID" =/ {product=$2; print name"\t"vendor"\t"product}
' | while IFS=$'\t' read -r name vendor product; do
  printf '"%s","%s","%s","%s","%s"\n' "IOHID" "$(safe_csv "$name")" "$vendor" "$product" "unknown" >> "$CSV"
done

REPAIR_FAILURES=0
if $REPAIR; then
  confirm_repair
  mkdir -p "$BACKUP_DIR"
  for domain in NSGlobalDomain com.apple.HIToolbox com.apple.universalaccess com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.mouse com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    /usr/bin/defaults export "$domain" "$BACKUP_DIR/${domain//\//_}.plist" >/dev/null 2>&1 || true
  done
  /usr/sbin/ioreg -r -c IOHIDDevice -l > "$BACKUP_DIR/iohid-before.txt" 2>/dev/null || true
  run_action "Restart the HID service" /bin/launchctl kickstart -k system/com.apple.hidd || REPAIR_FAILURES=$((REPAIR_FAILURES + 1))
  run_action "Refresh preference caches" /usr/bin/killall cfprefsd || REPAIR_FAILURES=$((REPAIR_FAILURES + 1))
  if $RESTART_BLUETOOTH; then
    run_action "Restart Bluetooth service" /bin/launchctl kickstart -k system/com.apple.bluetoothd || REPAIR_FAILURES=$((REPAIR_FAILURES + 1))
  fi
  sleep 2
  printf '\n===== Post-repair verification =====\n' >> "$REPORT"
  /usr/bin/pgrep -lf 'hidd|bluetoothd' >> "$REPORT" 2>> "$ERRORS" || true
  /usr/sbin/ioreg -r -c IOHIDDevice -l >> "$REPORT" 2>> "$ERRORS" || true
fi

DEVICE_COUNT="$(awk 'END {print NR-1}' "$CSV")"
HIDD_RUNNING=false; pgrep -x hidd >/dev/null 2>&1 && HIDD_RUNNING=true
BLUETOOTH_RUNNING=false; pgrep -x bluetoothd >/dev/null 2>&1 && BLUETOOTH_RUNNING=true
INPUT_SOURCE_COUNT="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -c 'KeyboardLayout Name\|Input Mode' || true)"
OVERALL="Healthy"
if ! $HIDD_RUNNING || [ "$DEVICE_COUNT" -eq 0 ]; then OVERALL="Attention required"; fi
[ "$REPAIR_FAILURES" -gt 0 ] && OVERALL="Repair failed"

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "hid_devices": $DEVICE_COUNT,
  "hidd_running": $HIDD_RUNNING,
  "bluetoothd_running": $BLUETOOTH_RUNNING,
  "input_source_indicators": $INPUT_SOURCE_COUNT,
  "repair_requested": $REPAIR,
  "restart_bluetooth_requested": $RESTART_BLUETOOTH,
  "dry_run": $DRY_RUN,
  "repair_failures": $REPAIR_FAILURES,
  "overall_status": "$OVERALL"
}
EOF

printf '\nKeyboard, mouse and trackpad diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
if [ "$REPAIR_FAILURES" -gt 0 ]; then exit 20; fi
[ "$OVERALL" = "Healthy" ] && exit 0
exit 10
