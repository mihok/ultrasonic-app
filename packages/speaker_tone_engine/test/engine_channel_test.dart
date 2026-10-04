import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speaker_tone_engine/speaker_tone_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('speaker_tone_engine');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'status' => {
          'sampleRate': 48000.0,
          'outputVolume': 0.75,
          'route': 'builtInSpeaker',
          'isRunning': false,
        },
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('status is decoded', () async {
    final status = await SpeakerToneEngine().status();
    expect(status.sampleRate, 48000);
    expect(status.outputVolume, 0.75);
    expect(status.route, OutputRoute.builtInSpeaker);
    expect(status.route.isBuiltIn, isTrue);
    expect(status.isRunning, isFalse);
  });

  test('start sends every segment and the master gain', () async {
    final program = ToneProgram(const [
      ToneSegment(duration: 1, startHz: 165, waveform: Waveform.saturated),
      ToneSegment.silence(0.5),
    ]);
    await SpeakerToneEngine().start(program, masterGain: 0.9);
    expect(calls.single.method, 'start');
    final args = calls.single.arguments as Map;
    expect(args['masterGain'], 0.9);
    final segments = (args['segments'] as List).cast<Map>();
    expect(segments, hasLength(2));
    expect(segments[0]['waveform'], 'saturated');
    expect(segments[0]['startHz'], 165.0);
    expect(segments[1]['amplitude'], 0.0);
  });

  test('stop is forwarded', () async {
    await SpeakerToneEngine().stop();
    expect(calls.single.method, 'stop');
  });

  test('events are decoded', () {
    EngineEvent? parse(Map<String, Object> m) => EngineEvent.fromMap(m);
    expect(
      (parse({'type': 'progress', 'position': 1.5})! as ProgressEvent).position,
      1.5,
    );
    final stopped =
        parse({'type': 'stopped', 'reason': 'routeChange'})! as StoppedEvent;
    expect(stopped.reason, StopReason.routeChange);
    expect(
      (parse({'type': 'stopped', 'reason': '???'})! as StoppedEvent).reason,
      StopReason.error,
    );
    expect(
      (parse({'type': 'volume', 'value': 0.5})! as VolumeEvent).volume,
      0.5,
    );
    expect(
      (parse({'type': 'route', 'route': 'external'})! as RouteEvent).route,
      OutputRoute.external,
    );
    expect(parse({'type': 'nope'}), isNull);
  });
}
