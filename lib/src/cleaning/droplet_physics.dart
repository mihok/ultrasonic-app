import 'dart:math' as math;

/// Surface tension of water at ~20 °C, N/m.
const double waterSurfaceTension = 0.072;

/// Density of water, kg/m³.
const double waterDensity = 998;

/// Natural frequency of shape-oscillation mode [mode] of a free liquid drop of
/// [radius] metres (Lord Rayleigh, 1879):
///
///     f = 1/(2π) · √( l(l−1)(l+2) · σ / (ρ R³) )
///
/// Mode 2 (the drop stretching into an egg and back) is the lowest one that
/// changes shape. Drops pinned in a speaker mesh are not free drops, so treat
/// this as a guide to which frequency band to sweep, not an exact target.
/// It lines up with the field result: a ~0.8 mm drop gives ~165 Hz, the tone
/// the "Water Eject" shortcut and Apple Watch-style ejectors settled on.
double rayleighFrequency(
  double radius, {
  int mode = 2,
  double surfaceTension = waterSurfaceTension,
  double density = waterDensity,
}) {
  assert(radius > 0 && mode >= 2);
  final k = mode * (mode - 1) * (mode + 2);
  return math.sqrt(k * surfaceTension / (density * radius * radius * radius)) /
      (2 * math.pi);
}

/// Inverse of [rayleighFrequency]: the drop radius in metres whose mode
/// resonates at [frequency] Hz.
double rayleighRadius(
  double frequency, {
  int mode = 2,
  double surfaceTension = waterSurfaceTension,
  double density = waterDensity,
}) {
  assert(frequency > 0 && mode >= 2);
  final k = mode * (mode - 1) * (mode + 2);
  final omega = 2 * math.pi * frequency;
  return math
      .pow(k * surfaceTension / (density * omega * omega), 1 / 3)
      .toDouble();
}
