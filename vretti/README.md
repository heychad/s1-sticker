# Vretti Keep Ready prototype

This experimental monitor holds a CoreBluetooth connection to one selected Vretti D463B and reads its standard model-number characteristic every minute. It does not write print commands, change printer settings, or print. If disconnected, it scans again. A bounded foreground run exits at the requested duration.

Build with `zsh vretti/build.sh`. Then run the executable in `.build-vretti/VrettiKeepReady.app/Contents/MacOS/` with the Mac's CoreBluetooth peripheral UUID and a duration in seconds (30–86,400). The UUID is local to the Mac and should be obtained from a scan; do not guess between devices with the same name.

The previous Bluetooth printer probe observed service `180A` and readable model characteristic `2A24`. A read is a connection check; whether it resets the printer's auto-off timer is unknown. Staying connected does not prove print availability or simultaneous use. Verify both with a foreground, status-only test before installing any login service. The Mac must remain awake, and the monitor cannot wake a powered-off printer. No login service is installed by this prototype.
