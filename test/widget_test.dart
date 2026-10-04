import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultrasonic_app/src/app.dart';
import 'package:ultrasonic_app/src/cleaning/cleaning_controller.dart';

const methods = MethodChannel('speaker_tone_engine');
const events = EventChannel('speaker_tone_engine/events');

class FakeNativeEngine {
  FakeNativeEngine({this.volume = 1, this.route = 'builtInSpeaker'});

  double volume;
  String route;
  final calls = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return {
          'sampleRate': 48000.0,
          'outputVolume': volume,
          'route': route,
          'isRunning': false,
        };
      }
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, s) {
          sink = s;
        },
      ),
    );
  }

  static void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  }
}

Future<CleaningController> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final controller = CleaningController(random: math.Random(1));
  // Not runAsync: the controller's streams must live in the test's fake-async
  // zone, or their events land after the pumps that should show them.
  controller.init();
  await tester.pumpWidget(UltrasonicApp(controller: controller));
  await tester.pump();
  return controller;
}

/// Lets an engine event reach the controller and its snackbar animate in.
Future<void> showSnackBars(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 750));
}

void main() {
  tearDown(FakeNativeEngine.uninstall);

  testWidgets('shows the program and the ready state', (tester) async {
    FakeNativeEngine().install();
    await pumpApp(tester);

    expect(find.text('Ultrasonic'), findsOneWidget);
    expect(find.text('Playing through the iPhone speakers'), findsOneWidget);
    expect(find.text('Volume 100%'), findsOneWidget);
    expect(find.text('Prime'), findsOneWidget);
    expect(find.text('Ejection bursts'), findsOneWidget);
    expect(find.text('Near-ultrasonic'), findsOneWidget);
    expect(find.textContaining('Start cleaning'), findsOneWidget);
  });

  testWidgets('warns when the volume is not at maximum', (tester) async {
    FakeNativeEngine(volume: 0.5).install();
    await pumpApp(tester);
    expect(find.text('Volume 50%'), findsOneWidget);
    expect(find.textContaining('all the way up'), findsOneWidget);
  });

  testWidgets('refuses to start through headphones', (tester) async {
    final native = FakeNativeEngine(route: 'external')..install();
    await pumpApp(tester);
    expect(find.textContaining('Headphones or Bluetooth'), findsOneWidget);
    await tester.tap(find.textContaining('Start cleaning'));
    await tester.pump();
    expect(native.calls.where((c) => c.method == 'start'), isEmpty);
  });

  testWidgets('mode switch regenerates the program', (tester) async {
    FakeNativeEngine().install();
    final c = await pumpApp(tester);
    final standard = c.program.duration;
    await tester.tap(find.text('Quick'));
    await tester.pump();
    expect(c.program.duration, lessThan(standard));
    await tester.tap(find.text('Dust'));
    await tester.pump();
    expect(find.text('Agitation'), findsOneWidget);
    expect(find.text('Ejection bursts'), findsNothing);
  });

  testWidgets('high-frequency switch removes the HF stages', (tester) async {
    FakeNativeEngine().install();
    await pumpApp(tester);
    final hfSwitch = find.text('High-frequency stages');
    await tester.scrollUntilVisible(
      hfSwitch,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(hfSwitch);
    await tester.pump();
    expect(find.text('Near-ultrasonic'), findsNothing);
    expect(find.text('Micro-droplet sweep'), findsNothing);
  });

  testWidgets('runs a program end to end', (tester) async {
    final native = FakeNativeEngine()..install();
    final c = await pumpApp(tester);
    final seed = c.seed;

    await tester.tap(find.textContaining('Start cleaning'));
    await tester.pump();
    final start = native.calls.singleWhere((call) => call.method == 'start');
    final args = start.arguments as Map;
    expect(args['segments'], c.program.tones.toWire());
    expect(args['masterGain'], c.program.masterGain);
    expect(find.text('Stop'), findsOneWidget);

    // Two seconds in: the resonance sweep.
    native.sink!.success({'type': 'progress', 'position': 4.0});
    await tester.pump();
    expect(find.text('Resonance sweep'), findsOneWidget);
    expect(find.textContaining('Hz'), findsWidgets);

    native.sink!.success({'type': 'stopped', 'reason': 'finished'});
    await showSnackBars(tester);
    expect(find.textContaining('Done.'), findsOneWidget);
    expect(find.textContaining('Start cleaning'), findsOneWidget);
    expect(c.seed, isNot(seed), reason: 'next run is a new variation');
  });

  testWidgets('stop button stops the engine', (tester) async {
    final native = FakeNativeEngine()..install();
    await pumpApp(tester);
    await tester.tap(find.textContaining('Start cleaning'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(native.calls.map((c) => c.method), contains('stop'));
    expect(find.textContaining('Start cleaning'), findsOneWidget);
  });

  testWidgets('a headphone connection mid-run is reported', (tester) async {
    final native = FakeNativeEngine()..install();
    await pumpApp(tester);
    await tester.tap(find.textContaining('Start cleaning'));
    await tester.pump();
    native.sink!.success({'type': 'route', 'route': 'external'});
    native.sink!.success({'type': 'stopped', 'reason': 'routeChange'});
    await showSnackBars(tester);
    expect(find.textContaining('Stopped: headphones'), findsOneWidget);
  });

  testWidgets('without the native engine it explains why', (tester) async {
    // What a non-iOS build sees: nothing registered on the channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          methods,
          (_) async => throw MissingPluginException(),
        );
    await pumpApp(tester);
    expect(find.textContaining('Playback needs an iPhone'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
