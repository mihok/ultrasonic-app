import 'dart:math' as math;

import 'package:speaker_tone_engine/dsp.dart';

import 'droplet_physics.dart';

/// Below this the micro-speaker barely makes pressure, and the amp's
/// excursion protection just turns it down.
const double speakerFloorHz = 100;

/// Bulk droplets sitting in or on the grille: ~0.4–1.1 mm radius.
final double bulkLowHz = math.max(speakerFloorHz, rayleighFrequency(1.1e-3));
final double bulkHighHz = rayleighFrequency(0.4e-3);

/// Small droplets wedged in the acoustic mesh pores: ~50–200 µm radius.
final double microLowHz = rayleighFrequency(0.2e-3);
final double microHighHz = rayleighFrequency(0.05e-3);

/// Lower edge of the "near-ultrasonic" band. Most adults hear little above it.
const double nearUltrasonicLowHz = 17000;

/// Level cap for anything above 1 kHz. Ears are most sensitive at 2–5 kHz,
/// so a full-scale sweep through there right next to the user is painful.
const double highFrequencyAmplitude = 0.35;
const double nearUltrasonicAmplitude = 0.5;

enum CleaningMode {
  quick('Quick', 'About 30 s. A light splash.'),
  standard('Standard', 'About 1 min. Use after rain, a sink or the pool.'),
  deep('Deep', 'About 2 min. Two full cycles for a dunking.'),
  dust(
    'Dust',
    'About 1 min. Shakes loose dust and lint. Packed debris needs a soft brush.',
  );

  const CleaningMode(this.label, this.description);
  final String label;
  final String description;
}

enum StageKind {
  prime('Prime'),
  resonanceSweep('Resonance sweep'),
  ejectionBursts('Ejection bursts'),
  pumping('Pumping'),
  agitation('Agitation'),
  microDroplets('Micro-droplet sweep'),
  nearUltrasonic('Near-ultrasonic'),
  finalPurge('Final purge'),
  rest('Rest');

  const StageKind(this.title);
  final String title;

  bool get isHighFrequency => this == microDroplets || this == nearUltrasonic;
}

class CleaningOptions {
  const CleaningOptions({
    this.mode = CleaningMode.standard,
    this.highFrequencyStages = true,
    this.ejectionHz = 165,
    this.intensity = 1,
    this.sampleRate = 48000,
    this.ultrasonicCeilingHz = 20000,
  }) : assert(intensity > 0 && intensity <= 1),
       assert(ejectionHz >= speakerFloorHz);

  final CleaningMode mode;

  /// Adds the micro-droplet sweep and the near-ultrasonic warble.
  final bool highFrequencyStages;

  /// Centre of the ejection bursts. 165 Hz is the widely used value; the
  /// best one varies a little by model and how much water is in there.
  final double ejectionHz;

  /// 0..1 scale on the whole program.
  final double intensity;

  /// Hardware sample rate. Caps the top of the near-ultrasonic band.
  final double sampleRate;

  /// Highest frequency to ask for. iPhone speakers fall off sharply above
  /// ~20 kHz, and 48 kHz audio cannot go past 24 kHz at all.
  final double ultrasonicCeilingHz;

  /// Top of the near-ultrasonic warble after the Nyquist guard.
  double get nearUltrasonicHighHz =>
      math.min(ultrasonicCeilingHz, sampleRate * nyquistGuard);

  CleaningOptions copyWith({
    CleaningMode? mode,
    bool? highFrequencyStages,
    double? ejectionHz,
    double? intensity,
    double? sampleRate,
  }) => CleaningOptions(
    mode: mode ?? this.mode,
    highFrequencyStages: highFrequencyStages ?? this.highFrequencyStages,
    ejectionHz: ejectionHz ?? this.ejectionHz,
    intensity: intensity ?? this.intensity,
    sampleRate: sampleRate ?? this.sampleRate,
    ultrasonicCeilingHz: ultrasonicCeilingHz,
  );
}

class ProgramStage {
  const ProgramStage({
    required this.kind,
    required this.detail,
    required this.start,
    required this.duration,
    required this.firstSegment,
    required this.endSegment,
  });

  final StageKind kind;

  /// What this stage does and why, with this program's actual numbers.
  final String detail;
  final double start;
  final double duration;
  final int firstSegment;
  final int endSegment;

  String get title => kind.title;
  double get end => start + duration;
}

class CleaningProgram {
  CleaningProgram({
    required this.options,
    required this.seed,
    required this.tones,
    required this.stages,
  });

  final CleaningOptions options;
  final int seed;
  final ToneProgram tones;
  final List<ProgramStage> stages;

  double get duration => tones.duration;

  /// Leaves a little headroom so the waveform never sits at 0 dBFS.
  double get masterGain => 0.95 * options.intensity;

  /// Index into [stages] for the stage playing at [time] seconds.
  int stageIndexAt(double time) {
    final i = tones.indexAt(time);
    return i < 0 ? 0 : tones.segments[i].tag;
  }
}

class _Recipe {
  const _Recipe({
    required this.cycles,
    required this.sweepPairs,
    required this.sweepSeconds,
    required this.bursts,
    required this.pumps,
    required this.agitations,
    required this.microSweeps,
    required this.nearUltrasonicSeconds,
    required this.purges,
    required this.primeSeconds,
  });

  final int cycles;
  final int sweepPairs;
  final double sweepSeconds;
  final int bursts;
  final int pumps;
  final int agitations;
  final int microSweeps;
  final double nearUltrasonicSeconds;
  final int purges;
  final double primeSeconds;

  static _Recipe of(CleaningMode mode) => switch (mode) {
    CleaningMode.quick => const _Recipe(
      cycles: 1,
      sweepPairs: 1,
      sweepSeconds: 3,
      bursts: 4,
      pumps: 1,
      agitations: 0,
      microSweeps: 1,
      nearUltrasonicSeconds: 2,
      purges: 1,
      primeSeconds: 1.5,
    ),
    CleaningMode.standard => const _Recipe(
      cycles: 1,
      sweepPairs: 1,
      sweepSeconds: 4,
      bursts: 8,
      pumps: 3,
      agitations: 0,
      microSweeps: 2,
      nearUltrasonicSeconds: 4,
      purges: 3,
      primeSeconds: 2,
    ),
    CleaningMode.deep => const _Recipe(
      cycles: 2,
      sweepPairs: 1,
      sweepSeconds: 4,
      bursts: 8,
      pumps: 3,
      agitations: 0,
      microSweeps: 2,
      nearUltrasonicSeconds: 4,
      purges: 4,
      primeSeconds: 2,
    ),
    CleaningMode.dust => const _Recipe(
      cycles: 1,
      sweepPairs: 2,
      sweepSeconds: 4,
      bursts: 0,
      pumps: 2,
      agitations: 8,
      microSweeps: 2,
      nearUltrasonicSeconds: 4,
      purges: 0,
      primeSeconds: 2,
    ),
  };
}

/// Builds a cleaning program from a seed.
///
/// The structure is fixed by the mode; the seed varies the details (burst
/// frequency, length and drive, pause lengths, AM rates, sweep timing, noise).
/// Varying them keeps a droplet that happens to sit at a pressure node for one
/// frequency from sitting there for all of them.
class ProgramGenerator {
  ProgramGenerator(this.options, {required this.seed})
    : _rng = math.Random(seed);

  final CleaningOptions options;
  final int seed;
  final math.Random _rng;

  final _segments = <ToneSegment>[];
  final _stages = <ProgramStage>[];
  double _time = 0;

  static CleaningProgram generate(
    CleaningOptions options, {
    required int seed,
  }) => ProgramGenerator(options, seed: seed)._build();

  double _between(double a, double b) => a + _rng.nextDouble() * (b - a);

  void _add(ToneSegment segment) {
    _segments.add(segment.copyWith(tag: _stages.length));
    _time += segment.duration;
  }

  void _stage(StageKind kind, String detail, void Function() body) {
    final first = _segments.length;
    final start = _time;
    body();
    if (_segments.length == first) return;
    _stages.add(
      ProgramStage(
        kind: kind,
        detail: detail,
        start: start,
        duration: _time - start,
        firstSegment: first,
        endSegment: _segments.length,
      ),
    );
  }

  CleaningProgram _build() {
    final recipe = _Recipe.of(options.mode);
    final hz = options.ejectionHz;
    final dropMm = rayleighRadius(hz) * 1000;
    final includeHigh =
        options.highFrequencyStages &&
        options.nearUltrasonicHighHz > nearUltrasonicLowHz + 500;

    _stage(
      StageKind.prime,
      'Ramps a ${hz.round()} Hz tone up to full level so the diaphragm '
      'starts moving the water in front of it.',
      () => _prime(recipe),
    );

    for (var cycle = 0; cycle < recipe.cycles; cycle++) {
      if (cycle > 0) {
        _stage(
          StageKind.rest,
          'Silence so water can drain back toward the grille.',
          () => _add(const ToneSegment.silence(3)),
        );
      }
      _stage(
        StageKind.resonanceSweep,
        'Log chirps across ${bulkLowHz.round()}–${bulkHighHz.round()} Hz, '
        'the shape resonances of 0.4–1.1 mm droplets.',
        () => _resonanceSweep(recipe),
      );
      _stage(
        StageKind.ejectionBursts,
        'Hard bursts around ${hz.round()} Hz (resonance of ~'
        '${dropMm.toStringAsFixed(1)} mm drops) with pauses so water pools '
        'at the grille between pushes, like Apple Watch Water Lock.',
        () => _ejectionBursts(recipe),
      );
      _stage(
        StageKind.pumping,
        'The low tone is pulsed 3–11 times a second so the diaphragm works '
        'like a piston pump.',
        () => _pumping(recipe),
      );
      _stage(
        StageKind.agitation,
        'Low-passed noise bursts shake loose dust and lint across the whole '
        'low band at once.',
        () => _agitation(recipe),
      );
      if (includeHigh) {
        _stage(
          StageKind.microDroplets,
          'Sweeps ${_khz(microLowHz)}–${_khz(microHighHz)} kHz for 50–200 µm '
          'droplets stuck in the mesh pores. Kept quieter: this band is the '
          'one ears are most sensitive to.',
          () => _microDroplets(recipe),
        );
        _stage(
          StageKind.nearUltrasonic,
          'Random warble across ${_khz(nearUltrasonicLowHz)}–'
          '${_khz(options.nearUltrasonicHighHz)} kHz, the top of what a 48 kHz '
          'DAC and the speaker can produce. Diaphragm motion is tiny here, so '
          'it is a finishing pass, not the main event.',
          () => _nearUltrasonic(recipe),
        );
      }
    }

    _stage(
      StageKind.finalPurge,
      'Longer low bursts to throw out whatever the earlier stages loosened.',
      () => _finalPurge(recipe),
    );

    return CleaningProgram(
      options: options,
      seed: seed,
      tones: ToneProgram(_segments),
      stages: List.unmodifiable(_stages),
    );
  }

  static String _khz(double hz) => (hz / 1000).toStringAsFixed(1);

  void _prime(_Recipe r) {
    _add(
      ToneSegment(
        duration: r.primeSeconds,
        startHz: options.ejectionHz,
        fadeIn: r.primeSeconds * 0.6,
        fadeOut: 0.02,
      ),
    );
  }

  void _resonanceSweep(_Recipe r) {
    for (var i = 0; i < r.sweepPairs; i++) {
      final up = r.sweepSeconds * _between(0.85, 1.15);
      final down = r.sweepSeconds * _between(0.85, 1.15);
      // Up and down share the turnaround frequency and have no fade between
      // them, so phase and pitch stay continuous.
      _add(
        ToneSegment(
          duration: up,
          startHz: bulkLowHz,
          endHz: bulkHighHz,
          fadeIn: 0.05,
          fadeOut: 0,
        ),
      );
      _add(
        ToneSegment(
          duration: down,
          startHz: bulkHighHz,
          endHz: bulkLowHz,
          fadeIn: 0,
          fadeOut: 0.05,
        ),
      );
    }
  }

  /// A saturated low burst that glides a few percent across its centre
  /// frequency, so it sweeps through the local resonance instead of
  /// guessing it.
  ToneSegment _burst(double centre, double duration, {double fadeOut = 0.03}) {
    final glide = 1 + _between(0.01, 0.04);
    final rising = _rng.nextBool();
    return ToneSegment(
      duration: duration,
      waveform: Waveform.saturated,
      startHz: rising ? centre / glide : centre * glide,
      endHz: rising ? centre * glide : centre / glide,
      drive: _between(1.8, 3),
      fadeIn: 0.015,
      fadeOut: fadeOut,
    );
  }

  void _ejectionBursts(_Recipe r) {
    for (var i = 0; i < r.bursts; i++) {
      final centre = options.ejectionHz * (1 + _between(-0.08, 0.08));
      _add(_burst(centre, _between(1.4, 2.4)));
      _add(ToneSegment.silence(_between(0.5, 0.9)));
    }
  }

  void _pumping(_Recipe r) {
    for (var i = 0; i < r.pumps; i++) {
      final t = r.pumps == 1 ? 0.5 : i / (r.pumps - 1);
      _add(
        ToneSegment(
          duration: _between(2.2, 2.8),
          waveform: Waveform.saturated,
          startHz: options.ejectionHz * (1 + _between(-0.05, 0.05)),
          drive: 2.2,
          amHz: 3 + 8 * t + _between(-0.5, 0.5),
          amDepth: 1,
          fadeIn: 0.02,
          fadeOut: 0.02,
        ),
      );
    }
  }

  void _agitation(_Recipe r) {
    for (var i = 0; i < r.agitations; i++) {
      _add(
        ToneSegment(
          duration: _between(1.6, 2.4),
          waveform: Waveform.noise,
          startHz: _between(150, 250),
          endHz: _between(400, 700),
          amplitude: 0.9,
          amHz: _between(2, 6),
          amDepth: 0.6,
          fadeIn: 0.03,
          fadeOut: 0.03,
          noiseSeed: _rng.nextInt(1 << 31) + 1,
        ),
      );
      _add(const ToneSegment.silence(0.4));
    }
  }

  void _microDroplets(_Recipe r) {
    for (var i = 0; i < r.microSweeps; i++) {
      final up = i.isEven;
      if (i > 0) _add(const ToneSegment.silence(0.3));
      _add(
        ToneSegment(
          duration: _between(2.6, 3.4),
          startHz: up ? microLowHz : microHighHz,
          endHz: up ? microHighHz : microLowHz,
          amplitude: highFrequencyAmplitude,
          fadeIn: 0.05,
          fadeOut: 0.05,
        ),
      );
    }
  }

  void _nearUltrasonic(_Recipe r) {
    final low = nearUltrasonicLowHz;
    final high = options.nearUltrasonicHighHz;
    final mid = (low + high) / 2;
    var remaining = r.nearUltrasonicSeconds;
    var hz = low;
    var rising = true;
    var first = true;
    while (remaining > 0.05) {
      var d = _between(0.3, 0.7);
      if (remaining - d < 0.2) d = remaining;
      final target = rising ? _between(mid, high) : _between(low, mid);
      final last = d >= remaining;
      _add(
        ToneSegment(
          duration: d,
          startHz: hz,
          endHz: target,
          amplitude: nearUltrasonicAmplitude,
          fadeIn: first ? 0.1 : 0,
          fadeOut: last ? 0.1 : 0,
        ),
      );
      remaining -= d;
      hz = target;
      rising = !rising;
      first = false;
    }
  }

  void _finalPurge(_Recipe r) {
    if (r.purges == 0) {
      // Dust mode: a last slow sweep down through the low band instead.
      _add(
        ToneSegment(
          duration: 4,
          startHz: bulkHighHz,
          endHz: bulkLowHz,
          fadeIn: 0.05,
          fadeOut: 0.3,
        ),
      );
      return;
    }
    for (var i = 0; i < r.purges; i++) {
      final last = i == r.purges - 1;
      final centre = options.ejectionHz * (1 + _between(-0.06, 0.06));
      _add(_burst(centre, _between(2.5, 3), fadeOut: last ? 0.3 : 0.03));
      if (!last) _add(const ToneSegment.silence(1));
    }
  }
}
