# macOS Keyboard, Mouse and Trackpad Diagnostics

A macOS support toolkit for diagnosing and repairing keyboard, mouse, trackpad, HID and Bluetooth input-service problems.

## Diagnostic script

```bash
chmod +x src/input_device_diagnostics.sh
./src/input_device_diagnostics.sh --hours 24
```

The diagnostic script collects USB, Bluetooth and IOHID device inventories, input sources, keyboard and pointing-device preferences, accessibility indicators, battery data and recent input events.

## Repair script

Preview the repair:

```bash
chmod +x src/input_device_repair.sh
sudo ./src/input_device_repair.sh --dry-run
```

Restart the HID service and refresh the logged-in user's input preference cache:

```bash
sudo ./src/input_device_repair.sh
```

Also restart Bluetooth:

```bash
sudo ./src/input_device_repair.sh --restart-bluetooth
```

## What the repair does

- Restarts the system HID service.
- Refreshes the preference cache for the logged-in user rather than the root account.
- Can optionally restart Bluetooth when wireless input devices are affected.
- Performs post-repair process and hardware verification.
- Supports dry-run, confirmations, logs and clear exit codes.

## Safety controls

- Repair mode requires administrator privileges.
- Bluetooth restart is optional because wireless devices may disconnect briefly.
- The repair does not remap keys, capture keystrokes, pair or forget devices, or change tracking speeds.
- Exit code `0` means success, `10` means cancelled, `20` means a repair warning or failure, `2` means invalid arguments and `3` means platform or privilege error.

## Validation note

The scripts include real repair actions and static validation support. Runtime behaviour must still be verified on the relevant macOS hardware and version before production deployment.

## Author

Dewald Pretorius — L2 IT Support Engineer
