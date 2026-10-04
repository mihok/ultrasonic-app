import Foundation

enum ToneProgramError: Error, CustomStringConvertible {
  case missingField(String)
  case invalidValue(String)
  case empty
  case tooLong

  var description: String {
    switch self {
    case .missingField(let key): return "Segment is missing \"\(key)\""
    case .invalidValue(let key): return "Segment has an invalid \"\(key)\""
    case .empty: return "Program has no segments"
    case .tooLong: return "Program is longer than \(Int(ToneRenderer.maxProgramSeconds)) s"
    }
  }
}

/// One segment of a tone program, decoded from Dart's `ToneSegment.toMap()`.
struct ToneSegmentSpec {
  enum Waveform: String { case sine, saturated, noise }
  enum Sweep: String { case linear, exponential }

  let duration: Double
  let waveform: Waveform
  let startHz: Double
  let endHz: Double
  let sweep: Sweep
  let amplitude: Double
  let drive: Double
  let amHz: Double
  let amDepth: Double
  let fadeIn: Double
  let fadeOut: Double
  let noiseSeed: UInt32

  init(map: [String: Any]) throws {
    func number(_ key: String) throws -> Double {
      guard let value = map[key] as? NSNumber else { throw ToneProgramError.missingField(key) }
      let d = value.doubleValue
      guard d.isFinite else { throw ToneProgramError.invalidValue(key) }
      return d
    }
    func text(_ key: String) throws -> String {
      guard let value = map[key] as? String else { throw ToneProgramError.missingField(key) }
      return value
    }

    duration = try number("duration")
    guard let waveform = Waveform(rawValue: try text("waveform")) else {
      throw ToneProgramError.invalidValue("waveform")
    }
    self.waveform = waveform
    startHz = try number("startHz")
    endHz = try number("endHz")
    guard let sweep = Sweep(rawValue: try text("sweep")) else {
      throw ToneProgramError.invalidValue("sweep")
    }
    self.sweep = sweep
    amplitude = try number("amplitude")
    drive = try number("drive")
    amHz = try number("amHz")
    amDepth = try number("amDepth")
    fadeIn = try number("fadeIn")
    fadeOut = try number("fadeOut")
    guard let seed = map["noiseSeed"] as? NSNumber else {
      throw ToneProgramError.missingField("noiseSeed")
    }
    noiseSeed = UInt32(truncatingIfNeeded: seed.int64Value)

    guard duration > 0 else { throw ToneProgramError.invalidValue("duration") }
    guard (0...1).contains(amplitude) else { throw ToneProgramError.invalidValue("amplitude") }
    guard (0...1).contains(amDepth) else { throw ToneProgramError.invalidValue("amDepth") }
    guard drive > 0 else { throw ToneProgramError.invalidValue("drive") }
    guard startHz >= 0, endHz >= 0, amHz >= 0 else { throw ToneProgramError.invalidValue("Hz") }
    guard fadeIn >= 0, fadeOut >= 0 else { throw ToneProgramError.invalidValue("fade") }
  }
}

/// Real-time synthesiser for a tone program.
///
/// `render(into:frameCount:)` runs on the Core Audio I/O thread inside the
/// `AVAudioSourceNode` render block, so it never allocates, locks, or calls
/// into Objective-C. Segments live in a raw buffer allocated up front so the
/// render path does not touch Swift array reference counting either.
///
/// The maths is kept sample-for-sample identical to the Dart `ToneRenderer`
/// (`lib/src/tone_renderer.dart`), which is where the unit tests live.
/// Change both together.
///
/// Threading: created on the main thread, then owned by the audio thread
/// until the engine has stopped. Nothing else reads or writes it meanwhile.
final class ToneRenderer: @unchecked Sendable {
  static let nyquistGuard = 0.45
  static let noiseHighPassHz = 40.0
  static let maxProgramSeconds = 600.0

  private struct Prepared {
    let waveform: ToneSegmentSpec.Waveform
    let frames: Int
    let fadeInFrames: Int
    let fadeOutFrames: Int
    let startHz: Double
    let endHz: Double
    let exponential: Bool
    let logRatio: Double
    let amplitude: Double
    let drive: Double
    let driveNorm: Double
    let amHz: Double
    let amDepth: Double
    let noiseSeed: UInt32
  }

  let sampleRate: Double
  let masterGain: Double
  let totalFrames: Int

  private let segments: UnsafeMutableBufferPointer<Prepared>
  private let maxHz: Double
  private let hpCoefficient: Double
  private let twoPi = 2 * Double.pi

  private var index = 0
  private var frame = 0
  private var phase = 0.0
  private var noiseState: UInt32 = 1
  private var lowPass = 0.0
  private var hpPrevIn = 0.0
  private var hpPrevOut = 0.0

  init(segments specs: [ToneSegmentSpec], sampleRate: Double, masterGain: Double) throws {
    guard !specs.isEmpty else { throw ToneProgramError.empty }
    let seconds = specs.reduce(0) { $0 + $1.duration }
    guard seconds <= Self.maxProgramSeconds else { throw ToneProgramError.tooLong }

    self.sampleRate = sampleRate
    self.masterGain = min(max(masterGain, 0), 1)
    maxHz = sampleRate * Self.nyquistGuard
    hpCoefficient = exp(-2 * Double.pi * Self.noiseHighPassHz / sampleRate)

    segments = .allocate(capacity: specs.count)
    var total = 0
    for (i, s) in specs.enumerated() {
      let frames = max(1, Int((s.duration * sampleRate).rounded()))
      let exponential = s.sweep == .exponential && s.startHz > 0 && s.endHz > 0
      (segments.baseAddress! + i).initialize(to: Prepared(
        waveform: s.waveform,
        frames: frames,
        fadeInFrames: min(Int((s.fadeIn * sampleRate).rounded()), frames / 2),
        fadeOutFrames: min(Int((s.fadeOut * sampleRate).rounded()), frames / 2),
        startHz: s.startHz,
        endHz: s.endHz,
        exponential: exponential,
        logRatio: exponential ? log(s.endHz / s.startHz) : 0,
        amplitude: s.amplitude,
        drive: s.drive,
        driveNorm: tanh(s.drive),
        amHz: s.amHz,
        amDepth: s.amDepth,
        noiseSeed: s.noiseSeed
      ))
      total += frames
    }
    totalFrames = total
    enterSegment(0)
  }

  deinit {
    segments.baseAddress!.deinitialize(count: segments.count)
    segments.deallocate()
  }

  var isFinished: Bool { index >= segments.count }

  /// Writes `frameCount` mono samples to `out` and returns how many came from
  /// the program (the rest is silence once it has finished).
  func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
    var produced = 0
    for i in 0..<frameCount {
      if index >= segments.count {
        out[i] = 0
        continue
      }
      out[i] = Float(nextSample())
      produced += 1
    }
    return produced
  }

  private func enterSegment(_ i: Int) {
    frame = 0
    guard i < segments.count else { return }
    let p = segments[i]
    if p.waveform == .noise {
      noiseState = p.noiseSeed == 0 ? 0x9E37_79B9 : p.noiseSeed
      lowPass = 0
      hpPrevIn = 0
      hpPrevOut = 0
    }
  }

  @inline(__always)
  private func nextNoise() -> Double {
    var x = noiseState
    x ^= x << 13
    x ^= x >> 17
    x ^= x << 5
    noiseState = x
    return Double(x) / 4_294_967_296.0 * 2 - 1
  }

  @inline(__always)
  private func advancePhase(_ hz: Double) {
    phase += twoPi * hz / sampleRate
    if phase >= twoPi { phase -= twoPi }
  }

  @inline(__always)
  private func nextSample() -> Double {
    let p = segments[index]
    var value = 0.0

    if p.amplitude > 0 {
      let u = Double(frame) / Double(p.frames)
      var hz = p.exponential
        ? p.startHz * exp(p.logRatio * u)
        : p.startHz + (p.endHz - p.startHz) * u
      hz = min(max(hz, 0), maxHz)

      var env = 1.0
      if frame < p.fadeInFrames {
        env = 0.5 - 0.5 * cos(Double.pi * Double(frame) / Double(p.fadeInFrames))
      }
      let remaining = p.frames - 1 - frame
      if remaining < p.fadeOutFrames {
        env *= 0.5 - 0.5 * cos(Double.pi * Double(remaining) / Double(p.fadeOutFrames))
      }

      let am = p.amDepth > 0
        ? 1 - p.amDepth * 0.5 * (1 - cos(twoPi * p.amHz * Double(frame) / sampleRate))
        : 1.0

      let osc: Double
      switch p.waveform {
      case .sine:
        osc = sin(phase)
        advancePhase(hz)
      case .saturated:
        osc = tanh(p.drive * sin(phase)) / p.driveNorm
        advancePhase(hz)
      case .noise:
        let cutoff = max(hz, 1)
        let a = 1 - exp(-twoPi * cutoff / sampleRate)
        lowPass += a * (nextNoise() - lowPass)
        let hp = lowPass - hpPrevIn + hpCoefficient * hpPrevOut
        hpPrevIn = lowPass
        hpPrevOut = hp
        // Unit-variance scaling for a one-pole low-pass fed with uniform
        // white noise (variance 1/3), then a soft clip to stay in range.
        let norm = (3 * (2 - a) / a).squareRoot()
        osc = tanh(0.5 * hp * norm)
      }

      value = min(max(masterGain * p.amplitude * env * am * osc, -1), 1)
    }

    frame += 1
    if frame >= p.frames {
      index += 1
      enterSegment(index)
    }
    return value
  }
}
