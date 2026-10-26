# How it works

## Background

On the MK1, NI's "MIDI mode" was never a hardware mode. NI's host software read the controller over its proprietary USB protocol and emitted MIDI on a virtual port. That software needed a kernel extension (`NIUSBMaschineController.kext`) that was never built for Apple Silicon. On a current Mac, nothing claims the MK1's vendor-specific USB interface, so a userspace program can talk to it directly through libusb.

## Components

```
┌────────────────────────── MK1 Bridge.app ─────────────────────────┐
│  MK1Bridge (Swift, menu bar)                                       │
│    • starts the daemon, restarts it after a crash or wake from sleep│
│    • reads the daemon's log lines to show status                   │
│    • SIGUSR1 toggle MIDI mode · SIGUSR2 panic · SIGHUP reload config│
│                                                                    │
│  Resources/daemon/  (Python, run from the venv)                    │
│    mk1_midi.py   main loop, MIDI mapping, LEDs, idle mode          │
│    mk1usb.py     USB protocol: buttons, knobs, pads, LEDs, displays │
│    screens.py    renders the two 255×64 displays with Pillow       │
│    glib_shim.py  tiny GLib-compatible main loop (macOS only)       │
└────────────────────────────────────────────────────────────────────┘
          │ libusb (pyusb)                         │ CoreMIDI (python-rtmidi)
     Maschine MK1                         virtual MIDI ports for your DAW
```

### USB (`mk1usb.py`)

| Endpoint | Direction | Content |
|---|---|---|
| EP 0x01 | out | Commands: request device info, LED states, DIN MIDI out, report rates |
| EP 0x81 | in | Button bitfield, knob positions (two-phase analog encoders), DIN MIDI in |
| EP 0x84 | in | 16 pad pressures (12 bit), about 700 reports per second |
| EP 0x08 | out | Display framebuffers (ST7529-style controller, 32 gray levels) |

The driver claims interface 0, resets the device, selects alternate setting 1 to enable EP 0x84 and EP 0x08, and sets the report rates.

### Hot-plugging

When the device disappears, the USB reader threads fail. The daemon then releases all held notes and polls every 2 s until the MK1 is back. The virtual MIDI ports belong to the daemon process and not to the device, so they stay available to your DAW the whole time.

### Files

| Path | Content |
|---|---|
| `~/Applications/MK1 Bridge.app` | The app with the daemon bundled inside |
| `~/Library/Application Support/MK1Bridge/venv` | Python 3.12 with pyusb, python-rtmidi and Pillow |
| `~/.config/mk1-midi/config.json` | Your mapping |
| `~/Library/Logs/MK1Bridge/mk1bridge.log` | App and daemon log (rotated at 5 MB) |

## Changes to upstream mk1-midi

The daemon is [mk1-midi](https://github.com/Cerv4ntez/mk1-midi) at commit `e8644b7`, a Linux driver. The macOS port changes the following:

- **Main loop:** on macOS the daemon runs on `glib_shim.py` instead of PyGObject. There is no session D-Bus, so the D-Bus interface is skipped.
- **MIDI:** the daemon uses the CoreMIDI backend of python-rtmidi. Ports get their full names (`Maschine MK1 Feedback`, …) because CoreMIDI shows only the port name.
- **USB:**
  - libusb is loaded from Homebrew (`/opt/homebrew/lib`). You can override the path with `MK1_LIBUSB`.
  - Kernel-driver detach and reattach are skipped, because macOS has no driver to hand the device back to.
  - If the USB reset makes macOS re-enumerate the device, the daemon claims it again. Set `MK1_NO_RESET=1` to skip the reset.
- **Fonts:** the displays use the system Arial family instead of fontconfig and DejaVu.
- **Remote control:** SIGUSR1, SIGUSR2 and SIGHUP handlers stand in for the D-Bus methods.
- **Defaults:** MIDI mode starts on by default. A default config file is written on first start. Idle mode starts after 30 minutes instead of 2.

The Linux code paths are unchanged, so the daemon still runs on Linux.

## Development

To run the daemon in a terminal, quit the menu bar app first:

```bash
~/Library/Application\ Support/MK1Bridge/venv/bin/python3 daemon/mk1_midi.py
MK1_MIDI_DEBUG=1 ...    # logs every button event
```

To rebuild after changes:

```bash
./build.sh --install
```
