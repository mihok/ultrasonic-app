import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:speaker_tone_engine/dsp.dart';

import '../cleaning/program_generator.dart';

/// Oscilloscope view of the signal around [position], drawn from the Dart
/// reference renderer (the same maths the native engine runs).
class WaveformScope extends StatelessWidget {
  const WaveformScope({
    super.key,
    required this.program,
    required this.position,
    required this.active,
  });

  static const double sampleRate = 48000;

  /// 25 ms: about four cycles of the 165 Hz ejection tone.
  static const int windowFrames = 1200;

  final CleaningProgram program;
  final double position;
  final bool active;

  Float32List _window() {
    final out = Float32List(windowFrames);
    if (!active) return out;
    ToneRenderer(
      program.tones.segments,
      sampleRate: sampleRate,
      masterGain: program.masterGain,
      startFrame: (position * sampleRate).round(),
    ).render(out);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.fromHeight(72),
        painter: WaveformScopePainter(
          samples: _window(),
          color: scheme.primary,
          axisColor: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class WaveformScopePainter extends CustomPainter {
  WaveformScopePainter({
    required this.samples,
    required this.color,
    required this.axisColor,
  });

  final Float32List samples;
  final Color color;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = axisColor
        ..strokeWidth = 0.5,
    );
    if (samples.isEmpty) return;
    final path = Path();
    final scaleY = mid - 2;
    for (var i = 0; i < samples.length; i++) {
      final dx = size.width * i / (samples.length - 1);
      final dy = mid - samples[i] * scaleY;
      i == 0 ? path.moveTo(dx, dy) : path.lineTo(dx, dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(WaveformScopePainter old) =>
      !identical(old.samples, samples) ||
      old.color != color ||
      old.axisColor != axisColor;
}
