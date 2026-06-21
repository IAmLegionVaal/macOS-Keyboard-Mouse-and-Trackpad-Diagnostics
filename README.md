# macOS Keyboard, Mouse and Trackpad Diagnostics

A read-only Bash toolkit for collecting keyboard, mouse, trackpad, HID, Bluetooth accessory, input-source, accessibility-setting, battery, and recent input-event evidence.

## Usage

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
- Text, CSV, and JSON reports

## Safety

The script does not remap keys, change tracking speed, reset Bluetooth, alter accessibility settings, pair devices, or modify input sources.

## Privacy

The toolkit does not capture keystrokes or record user input.

## Author

Dewald Pretorius — L2 IT Support Engineer
