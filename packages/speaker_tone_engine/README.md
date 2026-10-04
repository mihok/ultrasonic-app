# speaker_tone_engine

Local Flutter plugin used by the Ultrasonic app. It plays a list of
`ToneSegment`s through the iPhone's built-in speakers. The segments are
synthesised in real time inside an `AVAudioSourceNode` render block.

- `package:speaker_tone_engine/dsp.dart`: pure Dart (no Flutter). The segment
  model, a reference renderer that matches the Swift one sample for sample,
  and a WAV encoder.
- `package:speaker_tone_engine/speaker_tone_engine.dart`: the above, plus
  `SpeakerToneEngine` (method and event channels).
- `ios/speaker_tone_engine/Sources/speaker_tone_engine/`: `ToneRenderer.swift`
  (the real-time DSP), `ToneEngine.swift` (`AVAudioSession` and
  `AVAudioEngine`), and `SpeakerToneEnginePlugin.swift` (the bridge to Dart).

iOS only. On other platforms the channel calls throw `MissingPluginException`.
