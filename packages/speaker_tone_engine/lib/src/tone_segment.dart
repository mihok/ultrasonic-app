import 'dart:math' as math;

/// Shape of the signal a [ToneSegment] produces.
enum Waveform {
  /// Pure sine. Every watt goes into the fundamental, so it gives the most
  /// diaphragm excursion per unit of voice-coil heating.
  sine,

  /// Sine pushed through a `tanh` soft clipper. The flattened tops keep the
  /// diaphragm near full excursion for longer each cycle, which gives a harder
  /// push per cycle. The extra odd harmonics stay far below Nyquist as long as
  /// the fundamental is low (the program generator only uses it below 1 kHz).
  saturated,

  /// White noise through a low-pass (cutoff = the segment's frequency) and a
  /// 40 Hz DC-blocking high-pass. Broadband agitation for loose debris.
  noise,
}

/// How the frequency moves from [ToneSegment.startHz] to [ToneSegment.endHz].
enum Sweep {
  linear,

  /// Equal time per octave (a "log chirp"), so every resonance in a wide band
  /// gets the same dwell time.
  exponential,
}

/// One piece of a tone program: a tone, chirp, noise burst, or silence.
///
/// This is the wire contract between Dart and the native engine. The Swift
/// renderer (`ToneRenderer.swift`) and the Dart [ToneRenderer] implement the
/// same per-sample maths, so anything you can render and test in Dart is what
/// the phone plays.
class ToneSegment {
  const ToneSegment({
    required this.duration,
    this.waveform = Waveform.sine,
    this.startHz = 0,
    double? endHz,
    this.sweep = Sweep.exponential,
    this.amplitude = 1,
    this.drive = 1,
    this.amHz = 0,
    this.amDepth = 0,
    this.fadeIn = 0.01,
    this.fadeOut = 0.01,
    this.noiseSeed = 1,
    this.tag = 0,
  }) : endHz = endHz ?? startHz,
       assert(duration > 0),
       assert(amplitude >= 0 && amplitude <= 1),
       assert(amDepth >= 0 && amDepth <= 1),
       assert(drive > 0);

  /// A gap. The native engine keeps the oscillator phase running so the next
  /// tone starts cleanly.
  const ToneSegment.silence(double duration, {int tag = 0})
    : this(duration: duration, amplitude: 0, fadeIn: 0, fadeOut: 0, tag: tag);

  /// Seconds.
  final double duration;
  final Waveform waveform;

  /// Oscillator frequency (or noise low-pass cutoff) at the start, in Hz.
  final double startHz;

  /// Frequency at the end of the segment. Equal to [startHz] for a steady tone.
  final double endHz;
  final Sweep sweep;

  /// Peak level, 0..1 of digital full scale (before the program's master gain).
  final double amplitude;

  /// `tanh` drive for [Waveform.saturated]. 1 is barely bent, 3 is close to a
  /// rounded square wave.
  final double drive;

  /// Amplitude-modulation rate in Hz. 0 disables it.
  final double amHz;

  /// Amplitude-modulation depth, 0..1. 1 gates the tone fully off at the
  /// bottom of each AM cycle, which turns a tone into a train of pulses.
  final double amDepth;

  /// Raised-cosine fade lengths in seconds. Fades stop the speaker from being
  /// slammed by a step, which wastes power as a click.
  final double fadeIn;
  final double fadeOut;

  /// Seed for the noise generator (xorshift32). Non-zero.
  final int noiseSeed;

  /// Free-form label that is not sent to the engine. The app uses it as the
  /// index of the stage this segment belongs to.
  final int tag;

  bool get isSilent => amplitude == 0;

  /// Frequency at [u], the fraction of the segment that has elapsed (0..1).
  double frequencyAt(double u) {
    if (sweep == Sweep.exponential && startHz > 0 && endHz > 0) {
      return startHz * math.exp(math.log(endHz / startHz) * u);
    }
    return startHz + (endHz - startHz) * u;
  }

  /// Serialised form sent over the platform channel.
  Map<String, Object> toMap() => {
    'duration': duration,
    'waveform': waveform.name,
    'startHz': startHz,
    'endHz': endHz,
    'sweep': sweep.name,
    'amplitude': amplitude,
    'drive': drive,
    'amHz': amHz,
    'amDepth': amDepth,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'noiseSeed': noiseSeed,
  };

  factory ToneSegment.fromMap(Map<Object?, Object?> map, {int tag = 0}) {
    double d(String key) => (map[key]! as num).toDouble();
    return ToneSegment(
      duration: d('duration'),
      waveform: Waveform.values.byName(map['waveform']! as String),
      startHz: d('startHz'),
      endHz: d('endHz'),
      sweep: Sweep.values.byName(map['sweep']! as String),
      amplitude: d('amplitude'),
      drive: d('drive'),
      amHz: d('amHz'),
      amDepth: d('amDepth'),
      fadeIn: d('fadeIn'),
      fadeOut: d('fadeOut'),
      noiseSeed: map['noiseSeed']! as int,
      tag: tag,
    );
  }

  ToneSegment copyWith({double? amplitude, int? tag}) => ToneSegment(
    duration: duration,
    waveform: waveform,
    startHz: startHz,
    endHz: endHz,
    sweep: sweep,
    amplitude: amplitude ?? this.amplitude,
    drive: drive,
    amHz: amHz,
    amDepth: amDepth,
    fadeIn: fadeIn,
    fadeOut: fadeOut,
    noiseSeed: noiseSeed,
    tag: tag ?? this.tag,
  );

  @override
  String toString() =>
      'ToneSegment(${duration.toStringAsFixed(2)}s ${waveform.name} '
      '${startHz.toStringAsFixed(1)}→${endHz.toStringAsFixed(1)} Hz '
      'a=${amplitude.toStringAsFixed(2)})';
}

/// An ordered list of [ToneSegment]s plus a timeline index for the UI.
class ToneProgram {
  ToneProgram(List<ToneSegment> segments)
    : segments = List.unmodifiable(segments),
      _starts = _startTimes(segments);

  final List<ToneSegment> segments;
  final List<double> _starts;

  static List<double> _startTimes(List<ToneSegment> segments) {
    final starts = <double>[];
    var t = 0.0;
    for (final s in segments) {
      starts.add(t);
      t += s.duration;
    }
    starts.add(t);
    return starts;
  }

  /// Total length in seconds.
  double get duration => _starts.last;

  /// Start time of segment [index] in seconds.
  double startOf(int index) => _starts[index];

  /// Index of the segment playing at [time] seconds, clamped to the program.
  int indexAt(double time) {
    if (segments.isEmpty) return -1;
    if (time <= 0) return 0;
    if (time >= duration) return segments.length - 1;
    var lo = 0;
    var hi = segments.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Instantaneous frequency at [time], or null during silence.
  double? frequencyAt(double time) {
    final i = indexAt(time);
    if (i < 0) return null;
    final s = segments[i];
    if (s.isSilent) return null;
    final u = ((time - _starts[i]) / s.duration).clamp(0.0, 1.0);
    return s.frequencyAt(u);
  }

  List<Map<String, Object>> toWire() => [for (final s in segments) s.toMap()];
}
