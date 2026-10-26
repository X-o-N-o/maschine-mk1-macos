# maschine-mk1-macos

**Use the original Native Instruments Maschine MK1 as a MIDI controller on current macOS, including Apple Silicon. No Native Instruments drivers required.**

The Maschine MK1 (2009, USB `17cc:0808`) works with Native Instruments' drivers only up to macOS Mojave, and those drivers never ran on Apple Silicon. This project talks to the controller directly over USB. It turns the MK1 into a class-style MIDI controller with full LED and display feedback that works in any DAW or MIDI app: Ableton Live, Logic, Bitwig, AUTO/PILOT and others.

> Not affiliated with or endorsed by Native Instruments. *Maschine* and *Native Instruments* are trademarks of Native Instruments GmbH, used here only to name the hardware this project works with.

## Features

- **Pads:** notes with velocity, optional poly or channel aftertouch, and adjustable velocity curves.
- **Knobs:** all 11 encoders (8 knobs plus Volume, Tempo and Swing) send CCs, in absolute or relative mode.
- **Buttons:** every button sends a CC, either momentary or latching (toggle).
- **Group buttons A–H** switch the MIDI channel (1–8), so you can map one controller to eight layers.
- **LED feedback:** your DAW can light pads and buttons.
- **Both displays** show softkey names, knob values and the last control you touched, and a clock while idle.
- **DIN MIDI In/Out:** the MK1's 5-pin sockets show up as MIDI ports.
- **Hot-plugging:** you can unplug and replug at any time, and the MIDI ports stay put.
- A **menu bar app** shows the status, toggles MIDI mode, edits the configuration, can start at login, and restarts the driver after a crash or sleep.
- **MIDI mode** is on at launch. Toggle it on the hardware with **SHIFT + CONTROL**, as with NI's original MIDI mode.

## Requirements

- A Mac with **Apple Silicon** and **macOS 13 Ventura or later**. Intel Macs should work but are untested.
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/X-o-N-o/maschine-mk1-macos.git
cd maschine-mk1-macos
./build.sh --install
```

The script does four things:
1. Installs `libusb` and `python@3.12` via Homebrew.
2. Creates a Python environment in `~/Library/Application Support/MK1Bridge/`.
3. Builds **MK1 Bridge.app** into `~/Applications`.
4. Launches the app.

A grid icon appears in the menu bar. Plug in the MK1, and the pads light up dimly once MIDI mode is active.

To start it automatically, choose **Start at Login** in the menu.

## MIDI ports

| Port | Direction | Use it as |
|---|---|---|
| **Maschine MK1** | MK1 → computer | MIDI **input** in your DAW (notes and CCs) |
| **Maschine MK1 Feedback** | computer → MK1 | MIDI **output** for LED feedback |
| Maschine MK1 DIN In | MK1 socket → computer | Input from a device on the MK1's MIDI IN socket |
| Maschine MK1 DIN Out | computer → MK1 socket | Output to a device on the MK1's MIDI OUT socket |

See **[docs/DAW-SETUP.md](docs/DAW-SETUP.md)** for Ableton Live and other hosts.

## Default mapping

| Control | Message |
|---|---|
| Pads 1–16 | Notes 36–51 (C1–D#2), on the current group's channel |
| Knobs 1–8 | CC 14–21 |
| Volume / Tempo / Swing | CC 7 / 22 / 23 |
| Softkeys 1–8 | CC 102–109 |
| Group A–H | Select MIDI channel 1–8 |
| Transport and other buttons | CCs, see [docs/CONFIGURATION.md](docs/CONFIGURATION.md) |
| SHIFT + CONTROL | Toggle MIDI mode (sends nothing) |

Everything is configurable in `~/.config/mk1-midi/config.json`. Open it from the menu with **Edit Configuration…**, then choose **Reload Configuration**. The full reference is in **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)**.

## Idle mode

After **30 minutes** without input (setting `display.idle_minutes`), the MK1 turns its LEDs off and shows a clock. The first touch afterwards only wakes it and sends no MIDI, so you don't fire a note by accident. Set `idle_minutes` to `0` to disable idle mode.

## Menu bar app

| Item | What it does |
|---|---|
| Maschine / Daemon | Connection and driver status |
| MIDI Mode | Toggle MIDI mode (same as SHIFT + CONTROL) |
| All Notes Off | Release stuck notes on all channels |
| Edit Configuration… | Open `config.json` in TextEdit |
| Reload Configuration | Apply changes without restarting |
| Restart Daemon | Needed after changing `port_name` |
| Show Logs | Open `~/Library/Logs/MK1Bridge/` |
| Start at Login | Register as a login item |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Log says `cannot open Maschine MK1: Access denied` | Another program holds the device, such as an old NI driver or another MK1 tool. Quit it and choose **Restart Daemon**. |
| Log says `no reply to GET_DEVICE_INFO` | Unplug the MK1 and plug it back in. |
| Knobs jump in your DAW | Set the DAW's takeover mode to *Value Scaling*, or set `knobs.mode` to `relative`. |
| Pads too sensitive or not sensitive enough | Adjust `pads.threshold`, `pads.full_scale` and `pads.velocity_curve`. |
| Displays blank or washed out | Adjust `display.contrast`, one value per screen between 0 and 511. |
| Python errors after `brew upgrade` | Run `./build.sh --install` again. |

If you report a problem, please attach the last lines of `~/Library/Logs/MK1Bridge/mk1bridge.log`.

## Uninstall

```bash
./uninstall.sh           # keeps ~/.config/mk1-midi
./uninstall.sh --purge   # removes the configuration too
```

## How it works

```
Maschine MK1 ──USB (libusb / pyusb)──▶ mk1_midi.py (daemon) ──CoreMIDI──▶ DAW
  pads · knobs · buttons ──▶                                  ◀── LED feedback
  LEDs · 2 displays ◀──
                         MK1 Bridge.app: starts, watches and controls the daemon
```

**[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)** covers the architecture, the files involved and the changes made to the upstream Linux driver.

## Credits

- The USB driver and MIDI logic come from **[mk1-midi](https://github.com/Cerv4ntez/mk1-midi)** by Cerv4ntez (GPL-2.0-or-later), a Linux MIDI mode for the MK1. This project ports it to macOS and adds the menu bar app.
- The protocol knowledge builds on the Linux kernel's `snd-usb-caiaq` driver (Daniel Mack, Tim Ruetz), [cabl](https://github.com/shaduzlabs/cabl) by Vincenzo Pacella, and the reverse-engineering notes credited upstream.

## License

[GPL-2.0-or-later](LICENSE), the same as the upstream driver.
