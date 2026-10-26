# Changelog

## 1.0.0 – 2026-10-26

First public release.

- macOS port of the [mk1-midi](https://github.com/Cerv4ntez/mk1-midi) daemon (upstream `e8644b7`): CoreMIDI ports, Homebrew libusb, GLib stand-in main loop, system fonts for the displays
- MK1 Bridge menu bar app: status, MIDI mode toggle, all notes off, config edit/reload, logs, start at login, automatic restart after crashes and sleep
- Idle mode now starts after 30 minutes (upstream: 2)
- `build.sh` / `uninstall.sh`
