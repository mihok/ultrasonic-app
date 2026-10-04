// Renders a cleaning program to a 16-bit, 48 kHz WAV file, using the same
// generator and renderer as the app.
//
//   dart run tool/render_wav.dart --mode standard --seed 42 -o standard.wav
//
// Lets you listen to a program, inspect it in an audio editor, or AirDrop it to
// a phone and play it there without building the app.
import 'dart:io';
import 'dart:math' as math;

import 'package:speaker_tone_engine/dsp.dart';
import 'package:ultrasonic_app/src/cleaning/program_generator.dart';

const _usage = '''
Usage: dart run tool/render_wav.dart [options]

  --mode <quick|standard|deep|dust>   Program to render (default: standard)
  --seed <int>                        Procedural seed (default: random)
  --hz <number>                       Ejection centre frequency (default: 165)
  --no-high                           Leave out the high-frequency stages
  --intensity <0-1>                   Master level (default: 1)
  -o, --out <file.wav>                Output path (default: <mode>-<seed>.wav)
''';

void main(List<String> args) {
  var mode = CleaningMode.standard;
  int? seed;
  var hz = 165.0;
  var high = true;
  var intensity = 1.0;
  String? out;

  for (var i = 0; i < args.length; i++) {
    String value() {
      if (i + 1 >= args.length) _fail('Missing value for ${args[i]}');
      return args[++i];
    }

    switch (args[i]) {
      case '--mode':
        final name = value();
        mode = CleaningMode.values.firstWhere(
          (m) => m.name == name,
          orElse: () => _fail('Unknown mode "$name"'),
        );
      case '--seed':
        seed = int.tryParse(value()) ?? _fail('--seed takes an integer');
      case '--hz':
        hz = double.tryParse(value()) ?? _fail('--hz takes a number');
      case '--no-high':
        high = false;
      case '--intensity':
        intensity = double.tryParse(value()) ?? _fail('--intensity takes 0-1');
      case '-o' || '--out':
        out = value();
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        _fail('Unknown option ${args[i]}');
    }
  }

  if (hz < speakerFloorHz) _fail('--hz must be at least $speakerFloorHz');
  if (intensity <= 0 || intensity > 1) _fail('--intensity must be in (0, 1]');

  const sampleRate = 48000;
  final s = seed ?? math.Random().nextInt(1 << 31);
  final program = ProgramGenerator.generate(
    CleaningOptions(
      mode: mode,
      highFrequencyStages: high,
      ejectionHz: hz,
      intensity: intensity,
    ),
    seed: s,
  );
  final pcm = ToneRenderer.renderAll(
    program.tones.segments,
    sampleRate: sampleRate.toDouble(),
    masterGain: program.masterGain,
  );
  final path = out ?? '${mode.name}-$s.wav';
  File(path).writeAsBytesSync(encodeWav16(pcm, sampleRate: sampleRate));

  stdout.writeln(
    'Wrote $path: ${mode.label}, seed $s, '
    '${program.duration.toStringAsFixed(1)} s',
  );
  for (final stage in program.stages) {
    stdout.writeln(
      '  ${_clock(stage.start)}  ${stage.title.padRight(20)} '
      '${stage.duration.toStringAsFixed(1)} s',
    );
  }
}

String _clock(double seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toStringAsFixed(1).padLeft(4, '0');
  return '$m:$s';
}

Never _fail(String message) {
  stderr
    ..writeln(message)
    ..write(_usage);
  exit(64);
}
