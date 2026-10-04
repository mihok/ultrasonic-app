import AVFoundation
import QuartzCore
import UIKit

enum ToneEngineError: Error {
  case externalRoute
  case invalidProgram(String)
  case audio(String)

  var code: String {
    switch self {
    case .externalRoute: return "external_route"
    case .invalidProgram: return "invalid_program"
    case .audio: return "audio_error"
    }
  }

  var message: String {
    switch self {
    case .externalRoute:
      return "Audio is going to headphones or another device. Disconnect it so the program plays through the iPhone's own speakers."
    case .invalidProgram(let detail): return detail
    case .audio(let detail): return detail
    }
  }
}

/// Plays tone programs through the iPhone's built-in speakers.
///
/// The signal chain is as short as iOS allows:
///
///     AVAudioSourceNode (ToneRenderer, real-time thread)
///       → mainMixerNode → outputNode → speaker amp
///
/// The source node renders at the hardware sample rate so nothing gets
/// resampled, and the near-ultrasonic stage reaches the DAC as generated.
///
/// Main thread only, apart from the render block.
final class ToneEngine {
  enum Route: String {
    case builtInSpeaker, builtInReceiver, external, unknown
  }

  enum StopReason: String {
    case finished, user, interruption, routeChange, background, error
  }

  /// Called on the main thread with event dictionaries for the Dart side.
  var onEvent: (([String: Any]) -> Void)?

  private let session = AVAudioSession.sharedInstance()
  private var engine: AVAudioEngine?
  private var progressTimer: Timer?
  private var startedAt: CFTimeInterval = 0
  private var programSeconds: Double = 0
  private var stopAfterSeconds: Double = 0
  private var volumeObservation: NSKeyValueObservation?
  private var observers: [NSObjectProtocol] = []
  private var configurationObserver: NSObjectProtocol?
  private var idleSessionActive = false

  var isRunning: Bool { engine != nil }

  init() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
    ) { [weak self] _ in self?.routeChanged() })
    observers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification, object: session, queue: .main
    ) { [weak self] note in self?.interrupted(note) })
    observers.append(center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
    ) { [weak self] _ in
      self?.tearDown(reason: .error, message: "Audio services were reset.")
      self?.idleSessionActive = false
    })
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.tearDown(reason: .background) })

    volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
      let volume = Double(session.outputVolume)
      DispatchQueue.main.async { self?.emit(["type": "volume", "value": volume]) }
    }
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    volumeObservation?.invalidate()
  }

  func status() -> [String: Any] {
    activateIdleSession()
    return [
      "sampleRate": session.sampleRate,
      "outputVolume": Double(session.outputVolume),
      "route": currentRoute().rawValue,
      "isRunning": isRunning,
    ]
  }

  func start(segments: [ToneSegmentSpec], masterGain: Double) throws {
    tearDown(reason: nil)

    do {
      // .playback plays with the Ring/Silent switch on silent and stops other
      // apps' audio so it does not mix with the program.
      try session.setCategory(.playback, mode: .default, options: [])
      try? session.setPreferredSampleRate(48_000)
      try? session.setPreferredIOBufferDuration(0.01)
      try session.setActive(true)
      idleSessionActive = false
    } catch {
      throw ToneEngineError.audio("Could not activate the audio session: \(error.localizedDescription)")
    }

    // Full-scale cleaning tones are not something to send into earbuds.
    guard currentRoute() != .external else {
      activateIdleSession()
      throw ToneEngineError.externalRoute
    }

    let engine = AVAudioEngine()
    let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    let sampleRate = hardwareRate > 0 ? hardwareRate : session.sampleRate

    let renderer: ToneRenderer
    do {
      renderer = try ToneRenderer(segments: segments, sampleRate: sampleRate, masterGain: masterGain)
    } catch {
      activateIdleSession()
      throw ToneEngineError.invalidProgram(String(describing: error))
    }

    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
      activateIdleSession()
      throw ToneEngineError.audio("Unsupported sample rate \(sampleRate) Hz")
    }

    // Stereo out: on iPhone 7 and later the earpiece is the second speaker,
    // so writing the same signal to both channels drives both grilles.
    let source = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
      guard buffers.count > 0, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
        return noErr
      }
      let frames = Int(frameCount)
      let produced = renderer.render(into: left, frameCount: frames)
      if buffers.count > 1 {
        for channel in 1..<buffers.count {
          buffers[channel].mData?.copyMemory(from: left, byteCount: frames * MemoryLayout<Float>.size)
        }
      }
      if produced == 0 { isSilence.pointee = true }
      return noErr
    }

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1
    engine.prepare()
    do {
      try engine.start()
    } catch {
      activateIdleSession()
      throw ToneEngineError.audio("Could not start the audio engine: \(error.localizedDescription)")
    }

    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      self?.tearDown(reason: .error, message: "The audio hardware configuration changed.")
    }

    self.engine = engine
    programSeconds = Double(renderer.totalFrames) / sampleRate
    // The renderer pads with silence once it is done, so stopping a little
    // after the nominal end never cuts the final fade-out.
    stopAfterSeconds = programSeconds + session.outputLatency + session.ioBufferDuration + 0.25
    startedAt = CACurrentMediaTime()
    UIApplication.shared.isIdleTimerDisabled = true

    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  func stop() {
    tearDown(reason: .user)
  }

  // MARK: - Internals

  private func tick() {
    let elapsed = CACurrentMediaTime() - startedAt
    emit(["type": "progress", "position": min(elapsed, programSeconds)])
    if elapsed >= stopAfterSeconds {
      tearDown(reason: .finished)
    }
  }

  /// Stops playback (if any) and reports [reason] to Dart. A nil reason stops
  /// silently, for restarts.
  private func tearDown(reason: StopReason?, message: String? = nil) {
    guard let engine = engine else { return }
    progressTimer?.invalidate()
    progressTimer = nil
    engine.stop()
    self.engine = nil
    if let observer = configurationObserver {
      NotificationCenter.default.removeObserver(observer)
      configurationObserver = nil
    }
    UIApplication.shared.isIdleTimerDisabled = false
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    idleSessionActive = false
    activateIdleSession()

    if let reason = reason {
      var event: [String: Any] = ["type": "stopped", "reason": reason.rawValue]
      if let message = message { event["message"] = message }
      emit(event)
    }
  }

  /// A mixable, silent session that stays active between runs so the volume
  /// and route can be observed without interrupting the user's music.
  private func activateIdleSession() {
    guard !isRunning, !idleSessionActive else { return }
    do {
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      idleSessionActive = true
    } catch {
      idleSessionActive = false
    }
  }

  private func currentRoute() -> Route {
    guard let output = session.currentRoute.outputs.first else { return .unknown }
    switch output.portType {
    case .builtInSpeaker: return .builtInSpeaker
    case .builtInReceiver: return .builtInReceiver
    default: return .external
    }
  }

  private func routeChanged() {
    let route = currentRoute()
    emit(["type": "route", "route": route.rawValue])
    if isRunning && route == .external {
      tearDown(reason: .routeChange)
    }
  }

  private func interrupted(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .began
    else { return }
    tearDown(reason: .interruption)
  }

  private func emit(_ event: [String: Any]) {
    onEvent?(event)
  }
}
