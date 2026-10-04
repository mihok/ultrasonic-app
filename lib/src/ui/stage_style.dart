import 'package:flutter/material.dart';

import '../cleaning/program_generator.dart';

/// Colour for each stage on the timeline and in the stage list.
Color stageColor(StageKind kind) => switch (kind) {
  StageKind.prime => const Color(0xFF90A4AE),
  StageKind.resonanceSweep => const Color(0xFF4FC3F7),
  StageKind.ejectionBursts => const Color(0xFF00BCD4),
  StageKind.pumping => const Color(0xFF66BB6A),
  StageKind.agitation => const Color(0xFFFFB300),
  StageKind.microDroplets => const Color(0xFFAB47BC),
  StageKind.nearUltrasonic => const Color(0xFFEC407A),
  StageKind.finalPurge => const Color(0xFF29B6F6),
  StageKind.rest => const Color(0xFF9E9E9E),
};

String formatHz(double hz) => hz >= 1000
    ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 1 : 2)} kHz'
    : '${hz.round()} Hz';

String formatClock(double seconds) {
  final s = seconds.floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
