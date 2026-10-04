import 'dart:math' as math;
import 'dart:typed_data';

import 'tone_segment.dart';

const double _twoPi = 2 * math.pi;

/// Fraction of the sample rate above which no oscillator is allowed to go.
///
/// 0.45 × 48 kHz = 21.6 kHz: just under the iPhone DAC's reconstruction
/// filter, so nothing folds back down as an audible alias.
const double nyquistGuard = 0.45;

/// Cutoff of the DC blocker on the noise generator. Content below this only
/// moves the diaphragm without making useful pressure.
const double noiseHighPassHz = 40;

double _tanh(double x) => 1 - 2 / (math.exp(2 * x) + 1);

/// Sample-accurate Dart port of the native `ToneRenderer.swift`.
///
/// The iOS engine runs the same maths inside an `AVAudioSourceNode` render
/// callback. This copy exists so the signal can be unit tested, exported to
/// WAV and drawn on screen without a device.
class ToneRenderer {
  ToneRenderer(
    List<ToneSegment> segments, {
    required this.sampleRate,
    this.masterGain = 1,
    int startFrame = 0,
  }) : assert(sampleRate > 0),
       assert(masterGain >= 0 && masterGain <= 1),
       _segments = [for (final s in segments) _PreparedSegment(s, sampleRate)],
       _maxHz = sampleRate * nyquistGuard,
       _hpCoefficient = math.exp(-_twoPi * noiseHighPassHz / sampleRate) {
    totalFrames = _segments.fold(0, (sum, s) => sum + s.frames);
    _seek(startFrame);
  }

  final double sampleRate;
  final double masterGain;
  final List<_PreparedSegment> _segments;
  final double _maxHz;
  final double _hpCoefficient;

  late final int totalFrames;
  int _framesRendered = 0;

  int _index = 0;
  int _frame = 0;
  double _phase = 0;
  int _noiseState = 1;
  double _lowPass = 0;
  double _hpPrevIn = 0;
  double _hpPrevOut = 0;

  int get framesRendered => _framesRendered;
  bool get isFinished => _index >= _segments.length;

  /// Renders the whole program into one mono buffer.
  static Float32List renderAll(
    List<ToneSegment> segments, {
    required double sampleRate,
    double masterGain = 1,
  }) {
    final renderer = ToneRenderer(
      segments,
      sampleRate: sampleRate,
      masterGain: masterGain,
    );
    final out = Float32List(renderer.totalFrames);
    renderer.render(out);
    return out;
  }

  /// Fills [out] (from [offset], [count] frames) and returns how many frames
  /// came from the program. Anything past the end is silence.
  int render(Float32List out, [int offset = 0, int? count]) {
    final n = count ?? out.length - offset;
    var produced = 0;
    for (var i = 0; i < n; i++) {
      if (isFinished) {
        out[offset + i] = 0;
        continue;
      }
      out[offset + i] = _nextSample();
      produced++;
    }
    _framesRendered += produced;
    return produced;
  }

  void _seek(int startFrame) {
    var remaining = math.max(0, startFrame);
    _index = 0;
    while (_index < _segments.length && remaining >= _segments[_index].frames) {
      remaining -= _segments[_index].frames;
      _index++;
    }
    if (_index < _segments.length) {
      _enterSegment(_segments[_index]);
      _frame = remaining;
    }
  }

  void _enterSegment(_PreparedSegment p) {
    _frame = 0;
    if (p.segment.waveform == Waveform.noise) {
      final seed = p.segment.noiseSeed & 0xFFFFFFFF;
      _noiseState = seed == 0 ? 0x9E3779B9 : seed;
      _lowPass = 0;
      _hpPrevIn = 0;
      _hpPrevOut = 0;
    }
  }

  double _nextNoise() {
    var x = _noiseState;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _noiseState = x;
    return x / 4294967296.0 * 2 - 1;
  }

  double _nextSample() {
    final p = _segments[_index];
    final s = p.segment;
    var value = 0.0;

    if (s.amplitude > 0) {
      final u = _frame / p.frames;
      var hz = p.exponential
          ? s.startHz * math.exp(p.logRatio * u)
          : s.startHz + (s.endHz - s.startHz) * u;
      hz = hz.clamp(0.0, _maxHz);

      var env = 1.0;
      if (_frame < p.fadeInFrames) {
        env = 0.5 - 0.5 * math.cos(math.pi * _frame / p.fadeInFrames);
      }
      final remaining = p.frames - 1 - _frame;
      if (remaining < p.fadeOutFrames) {
        env *= 0.5 - 0.5 * math.cos(math.pi * remaining / p.fadeOutFrames);
      }

      final am = s.amDepth > 0
          ? 1 -
                s.amDepth *
                    0.5 *
                    (1 - math.cos(_twoPi * s.amHz * _frame / sampleRate))
          : 1.0;

      double osc;
      switch (s.waveform) {
        case Waveform.sine:
          osc = math.sin(_phase);
          _advancePhase(hz);
        case Waveform.saturated:
          osc = _tanh(s.drive * math.sin(_phase)) / p.driveNorm;
          _advancePhase(hz);
        case Waveform.noise:
          final cutoff = math.max(hz, 1.0);
          final a = 1 - math.exp(-_twoPi * cutoff / sampleRate);
          _lowPass += a * (_nextNoise() - _lowPass);
          final hp = _lowPass - _hpPrevIn + _hpCoefficient * _hpPrevOut;
          _hpPrevIn = _lowPass;
          _hpPrevOut = hp;
          // Unit-variance scaling for a one-pole low-pass fed with uniform
          // white noise (variance 1/3), then a soft clip to stay in range.
          final norm = math.sqrt(3 * (2 - a) / a);
          osc = _tanh(0.5 * hp * norm);
      }

      value = (masterGain * s.amplitude * env * am * osc).clamp(-1.0, 1.0);
    }

    _frame++;
    if (_frame >= p.frames) {
      _index++;
      if (_index < _segments.length) _enterSegment(_segments[_index]);
    }
    return value;
  }

  void _advancePhase(double hz) {
    _phase += _twoPi * hz / sampleRate;
    if (_phase >= _twoPi) _phase -= _twoPi;
  }
}

class _PreparedSegment {
  _PreparedSegment(this.segment, double sampleRate)
    : frames = math.max(1, (segment.duration * sampleRate).round()),
      exponential =
          segment.sweep == Sweep.exponential &&
          segment.startHz > 0 &&
          segment.endHz > 0,
      driveNorm = _tanh(segment.drive) {
    fadeInFrames = math.min((segment.fadeIn * sampleRate).round(), frames ~/ 2);
    fadeOutFrames = math.min(
      (segment.fadeOut * sampleRate).round(),
      frames ~/ 2,
    );
    logRatio = exponential ? math.log(segment.endHz / segment.startHz) : 0;
  }

  final ToneSegment segment;
  final int frames;
  final bool exponential;
  final double driveNorm;
  late final int fadeInFrames;
  late final int fadeOutFrames;
  late final double logRatio;
}
