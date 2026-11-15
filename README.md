# HearingCheck

An iPhone app for checking your own hearing with headphones. It tests each ear on its own,
low to high frequencies, and uses spatial audio to test how well you can tell where a sound
comes from.

This is a self-check, not a medical test. Levels are relative to your phone, headphones and
volume setting, not calibrated dB HL. It is most useful for spotting a difference between your
ears, or a change in your own results over time. If something looks off, see an audiologist.

## The tests

**Threshold test.** The app plays short beeps at 250 Hz to 8 kHz, with an optional extended
range of 10 to 16 kHz. You tap a button when you hear one. It uses the staircase method
audiologists use: 10 dB quieter after a beep you hear, 5 dB louder after one you miss. Each
beep plays in one ear only, with silence in the other. Beeps start after a random delay, and a
few trials are silent, so tapping on rhythm shows up as false taps.

You get an audiogram for both ears, a table of thresholds and a warning when your ears differ
by 15 dB or more at any frequency. Your first test is your baseline, and later tests show how
far each frequency moved since then.

**Balance test.** The same tone plays in your left ear, then your right, over and over. You
move a slider until both sound equally loud, then go to the next frequency (500 Hz to 8 kHz).
The result shows how many dB more one ear needed at each frequency, next to your previous run,
and a chart over time. It is a quick way to follow a one-sided change from day to day, such as
a dip in the high frequencies of one ear after a loud concert. The middle of the slider moves
by a hidden random amount on each frequency, so you can't line it up by eye.

Before each test you say how your ears feel: clear, or clogged on one or both sides. You can
change it later on the result screen. Once you have balance runs of both kinds, the result
screen shows the average for clogged runs next to the average for clear runs.

**Spatial test.** A noise burst, a low tone or a high tone plays from one of 8 directions
around your head, rendered with Apple's HRTF spatial audio. You tap where it came from. The
low tone tests the timing difference between your ears and the high tone tests the level
difference. Front/back mix-ups are normal with generic spatial audio and a still head.
Left/right mistakes are the ones to look at.

The threshold test does not use spatial audio on purpose. HRTF puts some of every sound in
both ears, so your better ear would hear tones meant for the other one.

## Getting good results

- Use the same headphones and the same volume every time. The setup screen shows a volume
  slider and tells you when the volume differs from your baseline.
- Sit somewhere quiet. On AirPods, use Noise Cancellation instead of Transparency or Adaptive.
- In Control Center, turn off Spatialize Stereo and head tracking.
- In Settings > Accessibility > Audio & Visual, turn off Mono Audio and Headphone
  Accommodations, and keep Balance centred.
- Tap only when you are sure you heard the beep.

## Build

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). There are no other
dependencies.

```sh
xcodegen generate
open HearingCheck.xcodeproj
```

Set your own `DEVELOPMENT_TEAM` in `project.yml` before you run it on a device. Results stay on
the phone as JSON in the app's Documents folder.

## License

MIT
