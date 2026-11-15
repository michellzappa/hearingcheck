# HearingCheck: agent notes

HearingCheck is an iPhone app (SwiftUI, iOS 18+) for a hearing self-check with headphones.
It has two tests:

- Threshold test: pure tones from 250 Hz to 8 kHz (optional 10 to 16 kHz), one ear at a time.
- Spatial test: a sound from one of 8 directions, rendered with HRTF. The user taps the direction.

No dependencies. No server. Results are plain JSON in `Documents/sessions.json`.

## Commands

- XcodeGen is the source of truth. `HearingCheck.xcodeproj` is generated and gitignored.
  Never edit it by hand.
- Generate the project: `xcodegen generate`
- Gate (build on mini-4p, from the repo root):
  `remote-build 'xcodegen generate -q && xcodebuild build -project HearingCheck.xcodeproj -scheme HearingCheck -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet'`
- Run on a device: `xcodegen generate && open HearingCheck.xcodeproj`, then run from Xcode
  with the iPhone selected. Signing uses team `992N457T8D` (automatic) from `project.yml`.
- There are no automated tests. mz tests the app by hand on an iPhone with headphones.

## How it works

- `Audio/AudioController.swift` owns the audio session (`.playback`, mode `.measurement`),
  the `AVAudioEngine` and the headphone route state. It has two signal paths:
  - `stereoPlayer` → main mixer. The threshold test uses this path. Each buffer is stereo
    and the other channel is digital silence, so the isolation is exact.
  - `spatialPlayer` (mono) → `AVAudioEnvironmentNode` (`.HRTFHQ`, output `.headphones`)
    → main mixer. Only the spatial test uses this path.
- Never route the threshold test through the environment node. HRTF puts sound in both ears,
  so the better ear hears tones meant for the other ear.
- Stimuli are 3 pulses of 220 ms with 20 ms cosine ramps. Without the ramps, clicks are
  broadband and the user hears a click instead of the tone.
- Levels are dB re digital full scale (dBFS). They are not calibrated dB HL. Results compare
  only when the headphones and the system volume are the same. The app cannot set the system
  volume; the setup screen shows `MPVolumeView`.
- `Test/ThresholdProcedure.swift`: modified Hughson-Westlake. Heard → 10 dB down, missed →
  5 dB up. Threshold = the lowest level heard on at least 2 ascending presentations, with at
  least half of the ascending presentations heard. Range -120 to -6 dBFS, maximum 30 trials.
- `Test/TestRunners.swift`: `ThresholdRunner` adds a random onset of 1.2 to 3.2 s and silent
  catch trials (12%). A tap outside the response window counts as a false alarm.
  `LocalizationRunner` plays each of 8 azimuths twice in random order with ±3 dB level jitter.
- AVAudio3D axes: +x right, +y up, -z forward. Azimuth 0 = front, 90 = right.
- The oldest threshold session is the baseline. `SessionDetailView` flags ear asymmetry of
  15 dB or more and a change of 10 dB or more worse than the baseline.

## Traps

- System features change the signal and the app cannot turn them off: Spatialize Stereo and
  head tracking, Mono Audio, Headphone Accommodations, Conversation Boost, AirPods
  Transparency or Adaptive mode. The setup screen tells the user to turn them off.
- The mini has Xcode 26.3 (iOS 26.2 SDK). Do not use iOS 27-only API.
- `SWIFT_VERSION` is 5.0. The audio classes are `@MainActor`; KVO and notification callbacks
  hop to the main actor with `Task { @MainActor in ... }`.
- UI strings contain no em dashes or en dashes.
