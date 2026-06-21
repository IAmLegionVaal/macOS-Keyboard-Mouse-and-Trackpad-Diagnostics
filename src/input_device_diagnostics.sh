#!/bin/bash
set -u

HOURS=24
OUTPUT_DIR=""

usage() {
  echo "Usage: input_device_diagnostics.sh [--hours N] [--output DIR]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./input-device-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/input-device-report.txt"
CSV="$OUTPUT_DIR/devices.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"
echo 'source,name,vendor_id,product_id,transport' > "$CSV"

section() {
  title="$1"
  shift
  { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true
}

safe_csv() {
  printf '%s' "$1" | sed 's/"/""/g'
}

section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "USB device inventory" /usr/sbin/system_profiler SPUSBDataType
section "Bluetooth device inventory" /usr/sbin/system_profiler SPBluetoothDataType
section "IOHID device inventory" /usr/sbin/ioreg -r -c IOHIDDevice -l
section "Input sources" /bin/bash -c 'defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null || true; defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null || true'
section "Keyboard preferences" /bin/bash -c 'defaults read -g InitialKeyRepeat 2>/dev/null || true; defaults read -g KeyRepeat 2>/dev/null || true; defaults read -g ApplePressAndHoldEnabled 2>/dev/null || true'
section "Mouse preferences" /bin/bash -c 'defaults read -g com.apple.mouse.scaling 2>/dev/null || true; defaults read com.apple.driver.AppleBluetoothMultitouch.mouse 2>/dev/null || true'
section "Trackpad preferences" /bin/bash -c 'defaults read -g com.apple.trackpad.scaling 2>/dev/null || true; defaults read com.apple.AppleMultitouchTrackpad 2>/dev/null || true; defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad 2>/dev/null || true'
section "Accessibility input settings" /bin/bash -c 'defaults read com.apple.universalaccess 2>/dev/null | grep -Ei "sticky|slow|mouse|trackpad|keyboard" || true'
section "Input-related processes" /bin/bash -c 'ps -Ao pid,user,etime,comm,args | grep -Ei "hidd|bluetoothd|WindowServer|TextInput|InputMethodKit" | grep -v grep || true'
section "Recent input-device events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process == \"hidd\") OR (process == \"bluetoothd\") OR (subsystem CONTAINS[c] \"HID\") OR (eventMessage CONTAINS[c] \"keyboard\") OR (eventMessage CONTAINS[c] \"mouse\") OR (eventMessage CONTAINS[c] \"trackpad\")' 2>/dev/null | tail -n 4000"

/usr/sbin/ioreg -r -c IOHIDDevice -l 2>/dev/null | awk -F' = ' '
  /"Product" =/ {name=$2; gsub(/^"|"$/,"",name)}
  /"VendorID" =/ {vendor=$2}
  /"ProductID" =/ {product=$2; print name"\t"vendor"\t"product}
' | while IFS=$'\t' read -r name vendor product; do
  printf '"%s","%s","%s","%s","%s"\n' \
    "IOHID" \
    "$(safe_csv "$name")" \
    "$vendor" \
    "$product" \
    "unknown" >> "$CSV"
done

DEVICE_COUNT="$(awk 'END {print NR-1}' "$CSV")"
HIDD_RUNNING=false
pgrep -x hidd >/dev/null 2>&1 && HIDD_RUNNING=true
BLUETOOTH_RUNNING=false
pgrep -x bluetoothd >/dev/null 2>&1 && BLUETOOTH_RUNNING=true
INPUT_SOURCE_COUNT="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -c 'KeyboardLayout Name\|Input Mode' || true)"
OVERALL="Healthy"
if ! $HIDD_RUNNING || [ "$DEVICE_COUNT" -eq 0 ]; then OVERALL="Attention required"; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "hid_devices": $DEVICE_COUNT,
  "hidd_running": $HIDD_RUNNING,
  "bluetoothd_running": $BLUETOOTH_RUNNING,
  "input_source_indicators": $INPUT_SOURCE_COUNT,
  "overall_status": "$OVERALL"
}
EOF

printf '\nKeyboard, mouse and trackpad diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
