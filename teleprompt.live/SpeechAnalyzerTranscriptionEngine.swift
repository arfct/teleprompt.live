import Foundation
import AVFoundation
import Speech

/// Default engine on iOS / macOS 26: Apple's SpeechAnalyzer + SpeechTranscriber.
/// Fully on-device, built for long-form live audio (no ~1 minute cap, so no
/// restart loop), and reports in-progress ("volatile") text so the
/// teleprompter can follow along within a beat of the speaker.
final class SpeechAnalyzerTranscriptionEngine: TranscriptionEngine {
  var onTranscript: ((String) -> Void)?
  var onError: ((String) -> Void)?

  /// SpeechTranscriber needs recent hardware; older devices fall back to
  /// the SFSpeechRecognizer engine.
  static var isSupported: Bool { SpeechTranscriber.isAvailable }

  private let audioEngine = AVAudioEngine()
  private var analyzer: SpeechAnalyzer?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var runTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var converter: AVAudioConverter?
  private var isAudioEngineRunning = false

  func start() {
    AVAudioApplication.requestRecordPermission { [weak self] granted in
      guard let self else { return }
      guard granted else {
        self.onError?("Microphone access is off. Enable it in Settings > Privacy & Security > Microphone to use the teleprompter.")
        return
      }
      self.runTask = Task { await self.run() }
    }
  }

  private func run() async {
    do {
      guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
        onError?("On-device transcription doesn't support \(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "this language") yet.")
        return
      }
      let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

      // The speech model is a system asset; download it the first time.
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
      try Task.checkCancellation()

      guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
        onError?("On-device transcription isn't available on this device.")
        return
      }

      let analyzer = SpeechAnalyzer(modules: [transcriber])
      self.analyzer = analyzer
      try await analyzer.prepareToAnalyze(in: analyzerFormat)

      resultsTask = Task { [weak self] in
        var lastEmitted = ""
        do {
          for try await result in transcriber.results {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            // Volatile updates often repeat the same text; skip re-matching.
            guard !text.isEmpty, text != lastEmitted else { continue }
            lastEmitted = text
            self?.onTranscript?(text)
          }
        } catch is CancellationError {
        } catch {
          self?.onError?("Speech recognition hiccup: \(error.localizedDescription)")
        }
      }

      let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
      inputContinuation = continuation
      try await analyzer.start(inputSequence: stream)
      try await MainActor.run { try self.beginAudioEngine(analyzerFormat: analyzerFormat) }
    } catch is CancellationError {
    } catch {
      onError?("Couldn't start transcription: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func beginAudioEngine(analyzerFormat: AVAudioFormat) throws {
    guard !isAudioEngineRunning else { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let inputNode = audioEngine.inputNode
    let micFormat = inputNode.outputFormat(forBus: 0)
    converter = micFormat == analyzerFormat ? nil : AVAudioConverter(from: micFormat, to: analyzerFormat)

    inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
      guard let self, let converted = self.convert(buffer, to: analyzerFormat) else { return }
      self.inputContinuation?.yield(AnalyzerInput(buffer: converted))
    }
    audioEngine.prepare()
    try audioEngine.start()
    isAudioEngineRunning = true
  }

  private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let converter else { return buffer }
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var consumed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return buffer
    }
    return error == nil && output.frameLength > 0 ? output : nil
  }

  func stop() {
    runTask?.cancel()
    runTask = nil
    if isAudioEngineRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
      isAudioEngineRunning = false
    }
    inputContinuation?.finish()
    inputContinuation = nil
    let analyzer = self.analyzer
    let resultsTask = self.resultsTask
    self.analyzer = nil
    self.resultsTask = nil
    Task {
      await analyzer?.cancelAndFinishNow()
      resultsTask?.cancel()
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
