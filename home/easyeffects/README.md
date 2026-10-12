# Easy Effects

Playback and voice capture both run through Easy Effects, so audio problems that look like bar bugs are often audio-graph problems.

## Signal chain

- **Playback:** apps → `easyeffects_sink` (the default sink) → the "Klipsch Stereo" preset → the USB DAC (`alsa_output.usb-0c76_USB_Audio-00`). The Sennheiser MOMENTUM 3 is present but isn't the chosen output.
- **Capture:** voxtype (`device = "default"`) records from `easyeffects_source`, not a raw mic.

## Troubleshooting

- **Volume keys:** they work because `easyeffectsrc` sets `[Audio] activateMonitorChannelVolumes=true` (upstream wwmm/easyeffects#5183). The same setting makes `easyeffects_source`'s own volume apply.
- **Flat voxtype waveform in the bar, though transcription still works:** check the source volume. At 27% the wave went flat; `wpctl set-volume <easyeffects_source id> 1.0` fixed it.
- **Silence with every link active and volumes at 1.0:** if `ee_soe_equalizer` outputs exact zeros while `easyeffects_sink` gets a full signal, the Stereo Tools effect (Calf) is the suspect. It went silent again within a second of a rebuilt equalizer, so the cause is in its input or settings, not stale state.
- **Check before touching Quickshell code:** run `pw-link -l` and look at both Easy Effects virtual device volumes before suspecting the bar.
