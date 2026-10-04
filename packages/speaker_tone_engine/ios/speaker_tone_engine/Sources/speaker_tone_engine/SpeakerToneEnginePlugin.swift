import Flutter
import UIKit

/// Bridges `ToneEngine` to Dart.
///
/// Method channel `speaker_tone_engine`:
///   - `status` → {sampleRate, outputVolume, route, isRunning}
///   - `start` {segments: [ToneSegment.toMap()], masterGain} → nil
///   - `stop` → nil
///
/// Event channel `speaker_tone_engine/events` sends dictionaries with a
/// `type` of `progress`, `stopped`, `volume` or `route`.
public class SpeakerToneEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let engine = ToneEngine()
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SpeakerToneEnginePlugin()
    let methods = FlutterMethodChannel(
      name: "speaker_tone_engine", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "speaker_tone_engine/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    instance.engine.onEvent = { [weak instance] event in
      instance?.eventSink?(event)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(engine.status())

    case "start":
      guard
        let args = call.arguments as? [String: Any],
        let rawSegments = args["segments"] as? [[String: Any]]
      else {
        result(FlutterError(code: "invalid_program", message: "Missing segments", details: nil))
        return
      }
      do {
        let segments = try rawSegments.map { try ToneSegmentSpec(map: $0) }
        let gain = (args["masterGain"] as? NSNumber)?.doubleValue ?? 1
        try engine.start(segments: segments, masterGain: gain)
        result(nil)
      } catch let error as ToneProgramError {
        result(FlutterError(code: "invalid_program", message: error.description, details: nil))
      } catch let error as ToneEngineError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        result(FlutterError(code: "audio_error", message: error.localizedDescription, details: nil))
      }

    case "stop":
      engine.stop()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    engine.stop()
    eventSink = nil
  }
}
