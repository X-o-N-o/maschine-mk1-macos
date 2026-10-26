# Configuration reference

The configuration file is `~/.config/mk1-midi/config.json`. The daemon creates it with defaults the first time it starts.

To change it:
1. Choose **Edit Configuration…** in the menu bar.
2. Edit and save the file.
3. Choose **Reload Configuration**.

`port_name` is the only setting that also needs **Restart Daemon**.

You can leave out any key, and the default applies. If the file is not valid JSON, the daemon falls back to all defaults and logs `config unreadable`.

## Top level

| Key | Default | Meaning |
|---|---|---|
| `port_name` | `"Maschine MK1"` | Base name of the MIDI ports. The others are named `… Feedback`, `… DIN In` and `… DIN Out`. |
| `hotkey` | `["shift", "control"]` | Button combination that toggles MIDI mode. These presses never send MIDI. |
| `start_in_midi_mode` | `true` | Enable MIDI mode as soon as the MK1 connects. |
| `hint_leds` | `true` | While MIDI mode is off, dimly light the hotkey buttons. |
| `group_mode` | `"channel"` | `"channel"`: groups A–H select MIDI channel 1–8. `"cc"`: groups send CCs like normal buttons. |
| `channel` | `1` | MIDI channel (1–16) when `group_mode` is `"cc"`. |

## `display`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Draw on the two displays. |
| `contrast` | `[253, 253]` | Contrast of the left and right panel (0–511). Panels differ, so tune each by eye. |
| `backlight` | `63` | Display backlight in MIDI mode (0–63). |
| `idle_backlight` | `0` | Backlight while MIDI mode is off. |
| `clock` | `true` | Show date and time while MIDI mode is off or idle. |
| `idle_minutes` | `30` | Minutes without input until idle mode starts (LEDs off, clock on). The first input after idle only wakes the MK1 and sends no MIDI. `0` disables idle mode. |

## `pads`

| Key | Default | Meaning |
|---|---|---|
| `base_note` | `36` | Note of pad 1. The pads use 16 consecutive notes. |
| `threshold` | `150` | Pressure that starts a note (0–4095). Lower values make the pads more sensitive. |
| `release` | `60` | Pressure below which the note ends. |
| `full_scale` | `3000` | Pressure that gives velocity 127. |
| `velocity_curve` | `"linear"` | One of `soft`, `linear`, `hard` or `fixed`. |
| `fixed_velocity` | `100` | Velocity used when the curve is `fixed`. |
| `velocity_window_ms` | `5` | How long after the first touch the daemon looks for the peak pressure. |
| `aftertouch` | `"off"` | One of `off`, `poly` or `channel`. |
| `idle_brightness` | `1` | Pad LED level while not hit in MIDI mode (0–63). |

## `knobs`

| Key | Default | Meaning |
|---|---|---|
| `mode` | `"absolute"` | `absolute` keeps a virtual 0–127 value per knob and group. `relative` sends 64 ± steps. |
| `turns` | `1.0` | Knob turns needed for the full 0–127 range in absolute mode. |
| `cc` | see below | CC number per knob. Remove a knob or set it to `null` to silence it. |
| `labels` | `{}` | Text shown on the displays, e.g. `{"knob_1": "Cutoff"}`. |

Default knob CCs:

| Knob | CC |
|---|---|
| `knob_1`–`knob_8` | 14–21 |
| `volume` | 7 |
| `tempo` | 22 |
| `swing` | 23 |

## `buttons`

| Key | Default | Meaning |
|---|---|---|
| `cc` | see below | CC number per button. Buttons send 127 on press and 0 on release. |
| `toggle` | `[]` | Buttons that latch on and off instead, e.g. `["mute", "solo"]`. |
| `labels` | `{}` | Softkey text shown on the displays, e.g. `{"softkey_1": "Rec Arm"}`. |

Default button CCs:

| Button | CC | Button | CC |
|---|---|---|---|
| `mute` | 24 | `control` | 85 |
| `solo` | 25 | `step` | 86 |
| `select` | 26 | `browse` | 87 |
| `duplicate` | 27 | `sampling` | 88 |
| `navigate` | 28 | `nav_left` | 89 |
| `pad_mode` (Keyboard) | 29 | `nav_right` | 90 |
| `pattern` | 30 | `autowrite` | 118 |
| `scene` | 31 | `snap` | 119 |
| `softkey_1`–`softkey_8` | 102–109 | `restart` | 110 |
| `note_repeat` | 9 | `step_left` | 111 |
| `group_a`–`group_h` | 52–59 (only when `group_mode` is `"cc"`) | `step_right` | 112 |
| | | `grid` | 113 |
| | | `play` | 114 |
| | | `rec` | 115 |
| | | `erase` | 116 |
| | | `shift` | 117 |

## LED feedback

Send MIDI to the **Maschine MK1 Feedback** port:

- **Pads:** a Note On with a pad's note lights that pad, with brightness equal to velocity / 2. Note Off or velocity 0 turns it off.
- **Buttons:** a CC with a button's CC number lights that button, with brightness equal to value / 2. Value 0 turns it off.
- In `channel` group mode, the MIDI channel of a feedback message selects the group (channel 1 → A, and so on). The LEDs show the feedback of the active group.

## Example

```json
{
  "display": { "idle_minutes": 60, "contrast": [240, 260] },
  "pads": { "velocity_curve": "soft", "aftertouch": "poly" },
  "knobs": { "mode": "relative", "labels": { "knob_1": "Cutoff", "knob_2": "Reso" } },
  "buttons": { "toggle": ["mute", "solo"], "labels": { "softkey_1": "Arm" } }
}
```
