import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speaker_tone_engine/dsp.dart';

import '../cleaning/program_generator.dart';
import 'stage_style.dart';

/// Frequency-over-time plot of a program, on a log frequency axis, with
/// coloured stage bands and a playhead.
class ProgramTimeline extends StatelessWidget {
  const ProgramTimeline({
    super.key,
    required this.program,
    required this.position,
    required this.showPlayhead,
  });

  final CleaningProgram program;
  final double position;
  final bool showPlayhead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Program timeline, ${program.stages.length} stages, '
          '${program.duration.round()} seconds',
      child: CustomPaint(
        size: const Size.fromHeight(170),
        painter: ProgramTimelinePainter(
          program: program,
          position: position,
          showPlayhead: showPlayhead,
          gridColor: theme.colorScheme.outlineVariant,
          labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
          playheadColor: theme.colorScheme.onSurface,
          bandColor: theme.colorScheme.tertiary,
        ),
      ),
    );
  }
}

class ProgramTimelinePainter extends CustomPainter {
  ProgramTimelinePainter({
    required this.program,
    required this.position,
    required this.showPlayhead,
    required this.gridColor,
    required this.labelStyle,
    required this.playheadColor,
    required this.bandColor,
  });

  static const double minHz = 80;
  static const double maxHz = 24000;
  static const double gutter = 30;

  final CleaningProgram program;
  final double position;
  final bool showPlayhead;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color playheadColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(gutter, 6, size.width, size.height - 6);
    final duration = program.duration;
    if (duration <= 0 || plot.width <= 0) return;

    double x(double t) => plot.left + plot.width * (t / duration);
    double y(double hz) {
      final f = hz.clamp(minHz, maxHz);
      return plot.bottom -
          plot.height * (math.log(f / minHz) / math.log(maxHz / minHz));
    }

    // Stage bands.
    for (final stage in program.stages) {
      canvas.drawRect(
        Rect.fromLTRB(x(stage.start), plot.top, x(stage.end), plot.bottom),
        Paint()..color = stageColor(stage.kind).withValues(alpha: 0.08),
      );
    }

    // The near-ultrasonic band, most adults hear little or nothing up here.
    canvas.drawRect(
      Rect.fromLTRB(plot.left, y(maxHz), plot.right, y(17000)),
      Paint()..color = bandColor.withValues(alpha: 0.10),
    );

    // Frequency grid.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (final (hz, label) in [
      (100.0, '100'),
      (1000.0, '1k'),
      (10000.0, '10k'),
      (20000.0, '20k'),
    ]) {
      final gy = y(hz);
      canvas.drawLine(Offset(plot.left, gy), Offset(plot.right, gy), grid);
      _label(canvas, label, Offset(gutter - 4, gy), alignRight: true);
    }

    // Frequency curves.
    for (final (i, segment) in program.tones.segments.indexed) {
      if (segment.isSilent) continue;
      final stage = program.stages[segment.tag];
      final t0 = program.tones.startOf(i);
      final steps = (segment.duration / duration * plot.width / 3).ceil().clamp(
        2,
        64,
      );
      final path = Path();
      for (var k = 0; k <= steps; k++) {
        final u = k / steps;
        final p = Offset(
          x(t0 + u * segment.duration),
          y(segment.frequencyAt(u)),
        );
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      final noise = segment.waveform == Waveform.noise;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = noise ? 7 : 2.5
          ..color = stageColor(stage.kind).withValues(alpha: noise ? 0.45 : 1),
      );
    }

    if (showPlayhead) {
      final px = x(position.clamp(0, duration));
      canvas.drawLine(
        Offset(px, plot.top),
        Offset(px, plot.bottom),
        Paint()
          ..color = playheadColor
          ..strokeWidth = 2,
      );
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? anchor.dx - tp.width : anchor.dx;
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(ProgramTimelinePainter old) =>
      old.program != program ||
      old.position != position ||
      old.showPlayhead != showPlayhead ||
      old.gridColor != gridColor ||
      old.labelStyle != labelStyle ||
      old.playheadColor != playheadColor ||
      old.bandColor != bandColor;
}
