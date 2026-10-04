import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speaker_tone_engine/speaker_tone_engine.dart';

import 'program_generator.dart';

/// Holds the current options, the generated program and the engine state.
class CleaningController extends ChangeNotifier {
  CleaningController({SpeakerToneEngine? engine, math.Random? random})
    : engine = engine ?? SpeakerToneEngine(),
      _random = random ?? math.Random() {
    _seed = _newSeed();
    _program = ProgramGenerator.generate(_options, seed: _seed);
  }

  final SpeakerToneEngine engine;
  final math.Random _random;
  final _notices = StreamController<String>.broadcast();
  StreamSubscription<EngineEvent>? _events;

  CleaningOptions _options = const CleaningOptions();
  late int _seed;
  late CleaningProgram _program;
  OutputStatus? _status;
  bool _engineAvailable = true;
  bool _running = false;
  bool _busy = false;
  double _position = 0;
  bool _disposed = false;

  CleaningOptions get options => _options;
  int get seed => _seed;
  CleaningProgram get program => _program;

  /// Null until the engine has answered (and always null off iOS).
  OutputStatus? get status => _status;

  /// False when there is no native engine (tests, or a non-iOS build).
  bool get engineAvailable => _engineAvailable;
  bool get isRunning => _running;
  bool get isBusy => _busy;

  /// Seconds into the running program.
  double get position => _position;

  /// One-off messages for the UI to show (snackbars).
  Stream<String> get notices => _notices.stream;

  int _newSeed() => _random.nextInt(1 << 31);

  Future<void> init() async {
    try {
      final status = await engine.status();
      _status = status;
      _events = engine.events.listen(_onEvent);
      if (status.sampleRate > 0 && status.sampleRate != _options.sampleRate) {
        _options = _options.copyWith(sampleRate: status.sampleRate);
        _regenerate();
      }
    } on MissingPluginException {
      _engineAvailable = false;
    } on PlatformException catch (e) {
      _engineAvailable = false;
      _notify(e.message ?? 'The audio engine is unavailable.');
    }
    _changed();
  }

  void setMode(CleaningMode mode) => _update(_options.copyWith(mode: mode));

  void setHighFrequencyStages(bool enabled) =>
      _update(_options.copyWith(highFrequencyStages: enabled));

  void setEjectionHz(double hz) => _update(_options.copyWith(ejectionHz: hz));

  void setIntensity(double intensity) =>
      _update(_options.copyWith(intensity: intensity));

  /// New seed, same options: a fresh variation of the same program.
  void shuffle() {
    if (_running) return;
    _seed = _newSeed();
    _regenerate();
    _changed();
  }

  Future<void> start() async {
    if (_running || _busy || !_engineAvailable) return;
    _busy = true;
    _changed();
    try {
      await engine.start(_program.tones, masterGain: _program.masterGain);
      _running = true;
      _position = 0;
    } on PlatformException catch (e) {
      _notify(e.message ?? 'Could not start audio.');
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _position = 0;
    _changed();
    try {
      await engine.stop();
    } on PlatformException catch (e) {
      _notify(e.message ?? 'Could not stop audio.');
    }
  }

  void _update(CleaningOptions next) {
    if (_running) return;
    _options = next;
    _regenerate();
    _changed();
  }

  void _regenerate() {
    _program = ProgramGenerator.generate(_options, seed: _seed);
  }

  void _onEvent(EngineEvent event) {
    switch (event) {
      case ProgressEvent(:final position):
        if (!_running) return;
        _position = position;
      case StoppedEvent(:final reason, :final message):
        final wasRunning = _running;
        _running = false;
        _position = 0;
        switch (reason) {
          case StopReason.finished:
            _notify(
              'Done. Still muffled? Run it again, then let the phone dry '
              'speaker-side down.',
            );
            // Next run gets a different variation.
            _seed = _newSeed();
            _regenerate();
          case StopReason.user:
            break;
          case StopReason.interruption:
            _notify('Stopped: a call or another app took over the audio.');
          case StopReason.routeChange:
            _notify('Stopped: headphones or a Bluetooth device connected.');
          case StopReason.background:
            if (wasRunning) _notify('Stopped: the app left the foreground.');
          case StopReason.error:
            _notify('Stopped: ${message ?? 'audio error'}');
        }
      case VolumeEvent(:final volume):
        _status = _status?.copyWith(outputVolume: volume);
      case RouteEvent(:final route):
        _status = _status?.copyWith(route: route);
    }
    _changed();
  }

  void _notify(String message) {
    if (!_disposed) _notices.add(message);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    if (_running) engine.stop().ignore();
    _notices.close();
    super.dispose();
  }
}
