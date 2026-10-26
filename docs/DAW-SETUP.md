# DAW setup

## Ableton Live

Open **Settings → Link, Tempo & MIDI** and set the MIDI ports:

| Port | In / Out | Track | Remote |
|---|---|---|---|
| Maschine MK1 | Input | On | On |
| Maschine MK1 Feedback | Output | Off | On |
| Maschine MK1 DIN In / DIN Out | In / Out | Only if something is plugged into the MK1's MIDI sockets | Off |

Leave **Control Surface** set to *None*.

- **Play instruments:** arm a MIDI track. The pads play notes 36–51, which matches Drum Rack's default layout.
- **Map controls:** press **Cmd+M**, click a parameter, then move a knob or press a button. Press **Cmd+M** again to finish.
- **Button LEDs:** with *Remote* enabled on the Feedback output, Live sends the state of mapped controls back. A button mapped to a track's mute lights while the track is muted.
- **Pad LEDs from clips:** set a MIDI track's output to *Maschine MK1 Feedback*. Notes 36–51 in that track light pads 1–16.
- **Knobs jump:** set **Takeover Mode** to *Value Scaling*, or use `"knobs": {"mode": "relative"}`.
- **Groups A–H** switch the MIDI channel. Each group can carry its own set of mappings.

## AUTO/PILOT

- Pick **Maschine MK1** as the MIDI input and map the controls in AUTO/PILOT's MIDI mapping.
- For LED feedback, select **Maschine MK1 Feedback** as the MIDI output, if your AUTO/PILOT version offers MIDI output for mappings.

## Other hosts (Logic Pro, Bitwig, Reason, …)

The MK1 shows up as a normal MIDI device. Use your host's *MIDI learn* to map controls. For LED feedback, route MIDI to **Maschine MK1 Feedback** as described in [CONFIGURATION.md](CONFIGURATION.md#led-feedback).

To check what the MK1 sends, use any MIDI monitor, such as [MIDI Monitor](https://www.snoize.com/midimonitor/).
