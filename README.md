# macOS Keyboard, Mouse and Trackpad Diagnostics

A Bash toolkit for collecting keyboard, mouse, trackpad, HID, Bluetooth accessory, input-source, accessibility-setting, battery, and recent input-event evidence. It also includes a guarded repair mode for input-service problems.

## Diagnostic usage

```bash
chmod +x src/input_device_diagnostics.sh
./src/input_device_diagnostics.sh --hours 24
```

## Checks performed

- USB, Bluetooth, and IOHID input-device inventory
- Keyboard layouts and enabled input sources
- Mouse, trackpad, key-repeat, and accessibility preference indicators
- Bluetooth accessory and battery information where reported by macOS
- Input-related services and recent HID, Bluetooth, keyboard, mouse, and trackpad events
- Text, CSV, JSON, error, and repair-action logs

## Repair usage

Preview the repair workflow:

```bash
sudo ./src/input_device_diagnostics.sh --repair --dry-run
```

Restart the HID service and refresh preference caches:

```bash
sudo ./src/input_device_diagnostics.sh --repair --yes
```

Bluetooth repair is separate because connected devices may temporarily disconnect:

```bash
sudo ./src/input_device_diagnostics.sh --restart-bluetooth --yes
```

Repair mode backs up relevant preference domains and IOHID evidence, restarts the HID service, refreshes preference caches, and performs post-repair verification. It does not remap keys, alter tracking speed, reset accessibility settings, pair or forget devices, or capture user input.

## Safety controls

- Repair mode requires root privileges
- `--dry-run` records intended actions without changing the Mac
- A confirmation prompt is shown unless `--yes` is supplied
- Bluetooth restart requires explicit opt-in
- Pre-repair preference exports and device evidence are stored in the report directory
- Every action and failure is recorded in `repair-actions.log`

## Exit codes

- `0` — healthy or successful repair
- `10` — attention still required or repair cancelled
- `20` — one or more repair actions failed
- `2` — invalid arguments
- `3` — wrong platform or insufficient privileges

## Privacy

The toolkit does not capture keystrokes or record user input.

## Validation note

The script has been statically reviewed for shell syntax and control flow. Runtime testing must be performed on a suitable macOS system before production use.

## Author

Dewald Pretorius — L2 IT Support Engineer
