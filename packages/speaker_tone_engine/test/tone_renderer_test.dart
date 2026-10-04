import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:speaker_tone_engine/dsp.dart';

const sr = 48000.0;

/// Power of [hz] in [x] (Goertzel), normalised so a full-scale sine ≈ 1.
double goertzel(Float32List x, double hz, {int start = 0, int? length}) {
  final n = length ?? x.length - start;
  final w = 2 * math.pi * hz / sr;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = 0; i < n; i++) {
    final s0 = x[start + i] + c * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final power = s1 * s1 + s2 * s2 - c * s1 * s2;
  return 4 * power / (n * n);
}

/// Frequency estimated from rising zero crossings in a window.
double zeroCrossingHz(Float32List x, int start, int length) {
  var crossings = 0;
  for (var i = start + 1; i < start + length; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) crossings++;
  }
  return crossings * sr / length;
}

double peak(Float32List x) => x.fold(0.0, (m, v) => math.max(m, v.abs()));

void main() {
  test('steady sine lands on the requested frequency and level', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 1, startHz: 165, fadeIn: 0, fadeOut: 0),
    ], sampleRate: sr);
    expect(out.length, 48000);
    expect(goertzel(out, 165), closeTo(1, 0.01));
    expect(goertzel(out, 330), lessThan(1e-6));
    expect(peak(out), closeTo(1, 1e-3));
  });

  test('master gain scales the output', () {
    final out = ToneRenderer.renderAll(
      const [ToneSegment(duration: 0.5, startHz: 200)],
      sampleRate: sr,
      masterGain: 0.5,
    );
    expect(peak(out), closeTo(0.5, 1e-3));
  });

  test('exponential sweep spends equal time per octave', () {
    // 100 -> 1600 Hz is 4 octaves in 4 s: one octave per second.
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 4, startHz: 100, endHz: 1600, fadeIn: 0),
    ], sampleRate: sr);
    final window = (0.1 * sr).round();
    for (final (t, hz) in [(0.5, 141.4), (1.5, 282.8), (2.5, 565.7)]) {
      final start = (t * sr).round() - window ~/ 2;
      expect(zeroCrossingHz(out, start, window), closeTo(hz, hz * 0.08));
    }
  });

  test('linear sweep is linear in time', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(
        duration: 2,
        startHz: 1000,
        endHz: 3000,
        sweep: Sweep.linear,
        fadeIn: 0,
      ),
    ], sampleRate: sr);
    final window = (0.05 * sr).round();
    final start = (1.0 * sr).round() - window ~/ 2;
    expect(zeroCrossingHz(out, start, window), closeTo(2000, 60));
  });

  test('fades start and end at silence', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 0.5, startHz: 300, fadeIn: 0.05, fadeOut: 0.05),
    ], sampleRate: sr);
    expect(out.first, 0);
    expect(out.last.abs(), lessThan(1e-6));
    // 10 ms into a 50 ms raised-cosine fade the envelope is 0.095.
    expect(peak(Float32List.sublistView(out, 0, 480)), lessThan(0.1));
  });

  test('phase runs continuously across segments (no clicks)', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 0.25, startHz: 165, fadeIn: 0, fadeOut: 0),
      ToneSegment(
        duration: 0.25,
        startHz: 165,
        endHz: 200,
        fadeIn: 0,
        fadeOut: 0,
      ),
      ToneSegment(duration: 0.25, startHz: 200, fadeIn: 0, fadeOut: 0),
    ], sampleRate: sr);
    // Largest step a 200 Hz full-scale sine can make between two samples.
    final maxStep = 2 * math.pi * 200 / sr * 1.01;
    for (var i = 1; i < out.length; i++) {
      expect((out[i] - out[i - 1]).abs(), lessThan(maxStep), reason: '@$i');
    }
  });

  test('silence is silent and keeps the program length', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 0.1, startHz: 165),
      ToneSegment.silence(0.2),
      ToneSegment(duration: 0.1, startHz: 165),
    ], sampleRate: sr);
    expect(out.length, (0.4 * sr).round());
    expect(peak(Float32List.sublistView(out, 4800, 14400)), 0);
  });

  test('saturated wave is louder at the fundamental but stays in range', () {
    List<ToneSegment> seg(Waveform w) => [
      ToneSegment(duration: 1, startHz: 165, waveform: w, drive: 3),
    ];
    final sine = ToneRenderer.renderAll(seg(Waveform.sine), sampleRate: sr);
    final sat = ToneRenderer.renderAll(seg(Waveform.saturated), sampleRate: sr);
    expect(peak(sat), lessThanOrEqualTo(1));
    expect(goertzel(sat, 165), greaterThan(goertzel(sine, 165) * 1.2));
    expect(goertzel(sat, 495), greaterThan(0.01)); // third harmonic
  });

  test('amplitude modulation with depth 1 gates the tone into pulses', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(
        duration: 1,
        startHz: 165,
        amHz: 5,
        amDepth: 1,
        fadeIn: 0,
        fadeOut: 0,
      ),
    ], sampleRate: sr);
    // The AM trough is at half a period: 0.1 s.
    final trough = (0.1 * sr).round();
    expect(
      peak(Float32List.sublistView(out, trough - 50, trough + 50)),
      lessThan(0.01),
    );
    expect(peak(Float32List.sublistView(out, 0, 480)), greaterThan(0.9));
  });

  test('noise is bounded, centred and deterministic for a seed', () {
    const seg = [
      ToneSegment(
        duration: 1,
        waveform: Waveform.noise,
        startHz: 400,
        noiseSeed: 1234,
      ),
    ];
    final a = ToneRenderer.renderAll(seg, sampleRate: sr);
    final b = ToneRenderer.renderAll(seg, sampleRate: sr);
    expect(a, b);
    expect(peak(a), lessThanOrEqualTo(1));
    final mean = a.fold(0.0, (s, v) => s + v) / a.length;
    expect(mean.abs(), lessThan(0.01));
    final rms = math.sqrt(a.fold(0.0, (s, v) => s + v * v) / a.length);
    expect(rms, greaterThan(0.2));

    final other = ToneRenderer.renderAll([
      const ToneSegment(
        duration: 1,
        waveform: Waveform.noise,
        startHz: 400,
        noiseSeed: 99,
      ),
    ], sampleRate: sr);
    expect(other, isNot(equals(a)));
  });

  test('low-passed noise keeps most energy below the cutoff', () {
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 2, waveform: Waveform.noise, startHz: 300),
    ], sampleRate: sr);
    final low = goertzel(out, 150);
    final high = goertzel(out, 6000);
    expect(low, greaterThan(high * 20));
  });

  test('frequencies are clamped below the Nyquist guard', () {
    // Asking for 30 kHz at 48 kHz would alias to 18 kHz; the guard holds it
    // at 21.6 kHz instead.
    final out = ToneRenderer.renderAll(const [
      ToneSegment(duration: 0.5, startHz: 30000, fadeIn: 0, fadeOut: 0),
    ], sampleRate: sr);
    expect(goertzel(out, 21600), closeTo(1, 0.02));
    expect(goertzel(out, 18000), lessThan(1e-4));
  });

  test('chunked rendering matches one-shot rendering', () {
    const program = [
      ToneSegment(duration: 0.3, startHz: 120, endHz: 480),
      ToneSegment(duration: 0.2, waveform: Waveform.noise, startHz: 500),
      ToneSegment.silence(0.1),
      ToneSegment(duration: 0.3, startHz: 17000, endHz: 20000),
    ];
    final whole = ToneRenderer.renderAll(program, sampleRate: sr);
    final renderer = ToneRenderer(program, sampleRate: sr);
    final chunked = Float32List(whole.length + 1000);
    var offset = 0;
    while (!renderer.isFinished) {
      offset += renderer.render(chunked, offset, 256);
    }
    expect(offset, whole.length);
    expect(Float32List.sublistView(chunked, 0, whole.length), whole);
    expect(renderer.framesRendered, whole.length);
  });

  test('startFrame seeks to the right segment', () {
    const program = [
      ToneSegment(duration: 1, startHz: 100),
      ToneSegment.silence(1),
      ToneSegment(duration: 1, startHz: 1000, fadeIn: 0),
    ];
    final r = ToneRenderer(program, sampleRate: sr, startFrame: 48000 + 100);
    final silent = Float32List(1000);
    r.render(silent);
    expect(peak(silent), 0);

    final r2 = ToneRenderer(program, sampleRate: sr, startFrame: 96000 + 4800);
    final tone = Float32List(4800);
    r2.render(tone);
    expect(zeroCrossingHz(tone, 0, 4800), closeTo(1000, 20));
  });

  test('segments survive the platform-channel round trip', () {
    const s = ToneSegment(
      duration: 1.5,
      waveform: Waveform.saturated,
      startHz: 150,
      endHz: 180,
      sweep: Sweep.linear,
      amplitude: 0.8,
      drive: 2.5,
      amHz: 7,
      amDepth: 0.9,
      fadeIn: 0.02,
      fadeOut: 0.03,
      noiseSeed: 77,
    );
    final back = ToneSegment.fromMap(s.toMap());
    expect(back.toMap(), s.toMap());
  });

  test('ToneProgram timeline lookups', () {
    final p = ToneProgram(const [
      ToneSegment(duration: 1, startHz: 100, endHz: 400),
      ToneSegment.silence(0.5),
      ToneSegment(duration: 2, startHz: 1000),
    ]);
    expect(p.duration, 3.5);
    expect(p.indexAt(-1), 0);
    expect(p.indexAt(0.99), 0);
    expect(p.indexAt(1.2), 1);
    expect(p.indexAt(1.5), 2);
    expect(p.indexAt(99), 2);
    expect(p.frequencyAt(0.5), closeTo(200, 1e-9)); // geometric midpoint
    expect(p.frequencyAt(1.2), isNull);
    expect(p.frequencyAt(2), 1000);
  });

  test('WAV encoder writes a valid 16-bit mono header', () {
    final samples = Float32List.fromList([0, 1, -1, 0.5]);
    final wav = encodeWav16(samples, sampleRate: 48000);
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint32(4, Endian.little), 36 + 8);
    expect(b.getUint32(24, Endian.little), 48000);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), 8);
    expect(b.getInt16(46, Endian.little), 32767);
    expect(b.getInt16(48, Endian.little), -32767);
    expect(wav.length, 44 + 8);
  });
}
