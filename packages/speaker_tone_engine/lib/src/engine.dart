import 'dart:async';

import 'package:flutter/services.dart';

import 'tone_segment.dart';

/// Where the audio is going right now, as reported by `AVAudioSession`.
enum OutputRoute {
  /// The bottom loudspeaker (with the earpiece as the second stereo speaker
  /// on iPhone 7 and later).
  builtInSpeaker,

  /// The earpiece (receiver).
  builtInReceiver,

  /// Headphones, Bluetooth, AirPlay, CarPlay, HDMI, USB...
  external,

  unknown;

  static OutputRoute parse(Object? value) => switch (value) {
    'builtInSpeaker' => builtInSpeaker,
    'builtInReceiver' => builtInReceiver,
    'external' => external,
    _ => unknown,
  };

  /// True when the program would come out of the phone itself, not out of
  /// headphones or a Bluetooth speaker.
  bool get isBuiltIn => this == builtInSpeaker || this == builtInReceiver;
}

/// Snapshot of the audio hardware.
class OutputStatus {
  const OutputStatus({
    required this.sampleRate,
    required this.outputVolume,
    required this.route,
    required this.isRunning,
  });

  factory OutputStatus.fromMap(Map<Object?, Object?> map) => OutputStatus(
    sampleRate: (map['sampleRate'] as num?)?.toDouble() ?? 48000,
    outputVolume: (map['outputVolume'] as num?)?.toDouble() ?? 0,
    route: OutputRoute.parse(map['route']),
    isRunning: map['isRunning'] == true,
  );

  OutputStatus copyWith({
    double? outputVolume,
    OutputRoute? route,
    bool? isRunning,
  }) => OutputStatus(
    sampleRate: sampleRate,
    outputVolume: outputVolume ?? this.outputVolume,
    route: route ?? this.route,
    isRunning: isRunning ?? this.isRunning,
  );

  /// Hardware sample rate in Hz (48 kHz on current iPhones).
  final double sampleRate;

  /// The system volume, 0..1. Apps cannot set it; the user has to.
  final double outputVolume;
  final OutputRoute route;
  final bool isRunning;
}

/// Why playback ended.
enum StopReason {
  finished,
  user,

  /// A phone call, Siri or an alarm took the audio session.
  interruption,

  /// Headphones or a Bluetooth device were connected mid-program. Stopping
  /// keeps full-scale tones from going straight into someone's ears.
  routeChange,

  /// The app was sent to the background.
  background,
  error;

  static StopReason parse(Object? value) => StopReason.values.firstWhere(
    (r) => r.name == value,
    orElse: () => StopReason.error,
  );
}

sealed class EngineEvent {
  const EngineEvent();

  static EngineEvent? fromMap(Map<Object?, Object?> map) =>
      switch (map['type']) {
        'progress' => ProgressEvent((map['position']! as num).toDouble()),
        'stopped' => StoppedEvent(
          StopReason.parse(map['reason']),
          message: map['message'] as String?,
        ),
        'volume' => VolumeEvent((map['value']! as num).toDouble()),
        'route' => RouteEvent(OutputRoute.parse(map['route'])),
        _ => null,
      };
}

/// Playback position in seconds since the program started.
class ProgressEvent extends EngineEvent {
  const ProgressEvent(this.position);
  final double position;
}

class StoppedEvent extends EngineEvent {
  const StoppedEvent(this.reason, {this.message});
  final StopReason reason;
  final String? message;
}

class VolumeEvent extends EngineEvent {
  const VolumeEvent(this.volume);
  final double volume;
}

class RouteEvent extends EngineEvent {
  const RouteEvent(this.route);
  final OutputRoute route;
}

/// Dart handle on the native iOS tone engine.
///
/// The engine runs an `AVAudioEngine` with an `AVAudioSourceNode` whose render
/// callback synthesises the [ToneSegment]s sample by sample on the real-time
/// audio thread, straight at the hardware sample rate.
class SpeakerToneEngine {
  SpeakerToneEngine({
    MethodChannel methodChannel = const MethodChannel('speaker_tone_engine'),
    EventChannel eventChannel = const EventChannel(
      'speaker_tone_engine/events',
    ),
  }) : _methods = methodChannel,
       _eventSource = eventChannel;

  final MethodChannel _methods;
  final EventChannel _eventSource;
  Stream<EngineEvent>? _events;

  /// Engine events: progress ticks (~20 Hz), stops, volume and route changes.
  Stream<EngineEvent> get events => _events ??= _eventSource
      .receiveBroadcastStream()
      .map((e) => EngineEvent.fromMap(e as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<EngineEvent>();

  /// Reads the output route, volume and hardware sample rate.
  Future<OutputStatus> status() async {
    final map = await _methods.invokeMapMethod<Object?, Object?>('status');
    return OutputStatus.fromMap(map ?? const {});
  }

  /// Starts playing [program]. Throws a [PlatformException] with code
  /// `external_route` if audio would go to headphones or Bluetooth.
  Future<void> start(ToneProgram program, {double masterGain = 1}) =>
      _methods.invokeMethod<void>('start', {
        'segments': program.toWire(),
        'masterGain': masterGain,
      });

  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
