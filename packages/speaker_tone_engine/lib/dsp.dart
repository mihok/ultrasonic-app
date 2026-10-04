/// Pure-Dart half of the tone engine: the segment model, the reference
/// renderer and a WAV encoder. Has no Flutter dependency, so command-line
/// tools can use it.
library;

export 'src/tone_renderer.dart';
export 'src/tone_segment.dart';
export 'src/wav_encoder.dart';
