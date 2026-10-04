import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:speaker_tone_engine/dsp.dart';
import 'package:ultrasonic_app/src/cleaning/droplet_physics.dart';
import 'package:ultrasonic_app/src/cleaning/program_generator.dart';

Iterable<double> frequencies(ToneSegment s) => [s.startHz, s.endHz];

void main() {
  group('droplet physics', () {
    test('a ~0.8 mm drop resonates near the 165 Hz field value', () {
      expect(rayleighFrequency(0.8e-3), closeTo(169, 2));
      expect(rayleighRadius(165) * 1000, closeTo(0.81, 0.01));
    });

    test('radius and frequency are inverses', () {
      for (final r in [30e-6, 0.2e-3, 1e-3, 2e-3]) {
        expect(rayleighRadius(rayleighFrequency(r)), closeTo(r, r * 1e-9));
      }
    });

    test('smaller drops ring higher (f ∝ R^-1.5)', () {
      final ratio = rayleighFrequency(0.1e-3) / rayleighFrequency(0.4e-3);
      expect(ratio, closeTo(8, 1e-9));
    });
  });

  group('program generator', () {
    test('same seed gives the same program, different seed does not', () {
      const options = CleaningOptions();
      final a = ProgramGenerator.generate(options, seed: 42);
      final b = ProgramGenerator.generate(options, seed: 42);
      final c = ProgramGenerator.generate(options, seed: 43);
      expect(a.tones.toWire(), b.tones.toWire());
      expect(a.tones.toWire(), isNot(c.tones.toWire()));
    });

    final expectedDurations = {
      CleaningMode.quick: (20.0, 35.0),
      CleaningMode.standard: (50.0, 75.0),
      CleaningMode.deep: (95.0, 140.0),
      CleaningMode.dust: (40.0, 70.0),
    };

    for (final mode in CleaningMode.values) {
      group(mode.name, () {
        for (final seed in [1, 7, 2024, 99999]) {
          final program = ProgramGenerator.generate(
            CleaningOptions(mode: mode),
            seed: seed,
          );
          final segments = program.tones.segments;

          test('seed $seed: length is in range', () {
            final (lo, hi) = expectedDurations[mode]!;
            expect(program.duration, inInclusiveRange(lo, hi));
          });

          test('seed $seed: every frequency is playable', () {
            for (final s in segments.where((s) => !s.isSilent)) {
              for (final f in frequencies(s)) {
                expect(f, lessThanOrEqualTo(20000), reason: '$s');
                expect(f, lessThanOrEqualTo(48000 * nyquistGuard));
                if (s.waveform != Waveform.noise) {
                  expect(f, greaterThanOrEqualTo(speakerFloorHz * 0.9));
                }
              }
            }
          });

          test('seed $seed: harmonics-rich waves stay low, loud stays low', () {
            for (final s in segments.where((s) => !s.isSilent)) {
              final top = math.max(s.startHz, s.endHz);
              if (s.waveform == Waveform.saturated) {
                expect(top, lessThan(1000), reason: '$s');
              }
              if (top > 1000) {
                expect(s.amplitude, lessThanOrEqualTo(0.5), reason: '$s');
              }
            }
          });

          test('seed $seed: stages tile the program in order', () {
            var expectedFirst = 0;
            var expectedStart = 0.0;
            for (final (i, stage) in program.stages.indexed) {
              expect(stage.firstSegment, expectedFirst);
              expect(stage.start, closeTo(expectedStart, 1e-9));
              for (var j = stage.firstSegment; j < stage.endSegment; j++) {
                expect(segments[j].tag, i);
              }
              expectedFirst = stage.endSegment;
              expectedStart = stage.end;
            }
            expect(expectedFirst, segments.length);
            expect(expectedStart, closeTo(program.duration, 1e-9));
          });

          test('seed $seed: renders without clipping or NaN', () {
            final pcm = ToneRenderer.renderAll(
              segments,
              sampleRate: 48000,
              masterGain: program.masterGain,
            );
            var peak = 0.0;
            for (final v in pcm) {
              expect(v.isFinite, isTrue);
              peak = math.max(peak, v.abs());
            }
            expect(peak, lessThanOrEqualTo(program.masterGain + 1e-6));
            expect(peak, greaterThan(0.9 * program.masterGain));
          });
        }
      });
    }

    test('water modes start with prime and end with a purge', () {
      for (final mode in [
        CleaningMode.quick,
        CleaningMode.standard,
        CleaningMode.deep,
      ]) {
        final p = ProgramGenerator.generate(
          CleaningOptions(mode: mode),
          seed: 5,
        );
        expect(p.stages.first.kind, StageKind.prime);
        expect(p.stages.last.kind, StageKind.finalPurge);
        expect(
          p.stages.map((s) => s.kind),
          containsAllInOrder([
            StageKind.resonanceSweep,
            StageKind.ejectionBursts,
            StageKind.pumping,
            StageKind.microDroplets,
            StageKind.nearUltrasonic,
          ]),
        );
      }
    });

    test('deep mode runs two cycles with a rest between', () {
      final p = ProgramGenerator.generate(
        const CleaningOptions(mode: CleaningMode.deep),
        seed: 5,
      );
      final kinds = p.stages.map((s) => s.kind).toList();
      expect(kinds.where((k) => k == StageKind.ejectionBursts), hasLength(2));
      expect(kinds, contains(StageKind.rest));
    });

    test('dust mode uses noise agitation and no ejection bursts', () {
      final p = ProgramGenerator.generate(
        const CleaningOptions(mode: CleaningMode.dust),
        seed: 5,
      );
      final kinds = p.stages.map((s) => s.kind);
      expect(kinds, contains(StageKind.agitation));
      expect(kinds, isNot(contains(StageKind.ejectionBursts)));
      expect(
        p.tones.segments.where((s) => s.waveform == Waveform.noise),
        isNotEmpty,
      );
    });

    test('turning off high-frequency stages keeps everything below 1 kHz', () {
      final p = ProgramGenerator.generate(
        const CleaningOptions(highFrequencyStages: false),
        seed: 3,
      );
      expect(p.stages.where((s) => s.kind.isHighFrequency), isEmpty);
      for (final s in p.tones.segments) {
        expect(math.max(s.startHz, s.endHz), lessThan(1000));
      }
    });

    test('near-ultrasonic stage reaches the ceiling band', () {
      final p = ProgramGenerator.generate(const CleaningOptions(), seed: 11);
      final stage = p.stages.firstWhere(
        (s) => s.kind == StageKind.nearUltrasonic,
      );
      final segs = p.tones.segments.sublist(
        stage.firstSegment,
        stage.endSegment,
      );
      final all = segs.expand(frequencies);
      expect(all.reduce(math.min), greaterThanOrEqualTo(nearUltrasonicLowHz));
      expect(all.reduce(math.max), greaterThan(18500));
      // Turnarounds are continuous: each segment starts where the last ended.
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].startHz, segs[i - 1].endHz);
      }
    });

    test('a 44.1 kHz device caps the warble under its Nyquist guard', () {
      final p = ProgramGenerator.generate(
        const CleaningOptions(sampleRate: 44100),
        seed: 11,
      );
      for (final s in p.tones.segments) {
        expect(math.max(s.startHz, s.endHz), lessThanOrEqualTo(44100 * 0.45));
      }
    });

    test('ejection bursts follow the chosen centre frequency', () {
      for (final hz in [140.0, 165.0, 200.0]) {
        final p = ProgramGenerator.generate(
          CleaningOptions(ejectionHz: hz),
          seed: 8,
        );
        final stage = p.stages.firstWhere(
          (s) => s.kind == StageKind.ejectionBursts,
        );
        final bursts = p.tones.segments
            .sublist(stage.firstSegment, stage.endSegment)
            .where((s) => !s.isSilent);
        for (final b in bursts) {
          final centre = math.sqrt(b.startHz * b.endHz);
          expect(centre, closeTo(hz, hz * 0.09));
          expect(b.waveform, Waveform.saturated);
        }
      }
    });

    test('bursts are separated by pauses', () {
      final p = ProgramGenerator.generate(const CleaningOptions(), seed: 2);
      final stage = p.stages.firstWhere(
        (s) => s.kind == StageKind.ejectionBursts,
      );
      final segs = p.tones.segments.sublist(
        stage.firstSegment,
        stage.endSegment,
      );
      for (var i = 0; i < segs.length; i++) {
        expect(segs[i].isSilent, i.isOdd);
      }
    });

    test('intensity scales master gain', () {
      final p = ProgramGenerator.generate(
        const CleaningOptions(intensity: 0.5),
        seed: 1,
      );
      expect(p.masterGain, closeTo(0.475, 1e-9));
    });

    test('stageIndexAt follows the timeline', () {
      final p = ProgramGenerator.generate(const CleaningOptions(), seed: 1);
      for (final (i, stage) in p.stages.indexed) {
        expect(p.stageIndexAt(stage.start + stage.duration / 2), i);
      }
    });
  });
}
