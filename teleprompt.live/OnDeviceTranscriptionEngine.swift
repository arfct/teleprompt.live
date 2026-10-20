import Foundation
import AVFoundation
import Speech

/// Default engine: transcribes speech entirely on-device via Apple's Speech
/// framework. No network call, no API key, works offline.
final class OnDeviceTranscriptionEngine: TranscriptionEngine {
  var onTranscript: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var restartTimer: Timer?
  private var isAudioEngineRunning = false

  // SFSpeechRecognitionTask historically caps continuous audio around a
  // minute; restart the recognition task periodically (keeping the audio
  // engine running underneath) so long scripts don't silently stop
  // transcribing partway through.
  private let restartInterval: TimeInterval = 50

  func start() {
    AVAudioApplication.requestRecordPermission { [weak self] granted in
      guard let self else { return }
      guard granted else {
        self.onError?("Microphone access is off. Enable it in Settings > Privacy & Security > Microphone to use the teleprompter.")
        return
      }
      SFSpeechRecognizer.requestAuthorization { authStatus in
        DispatchQueue.main.async {
          guard authStatus == .authorized else {
            self.onError?("Speech recognition access is off. Enable it in Settings > Privacy & Security > Speech Recognition.")
            return
          }
          self.beginAudioEngineIfNeeded()
          self.startRecognitionTask()
          self.restartTimer = Timer.scheduledTimer(withTimeInterval: self.restartInterval, repeats: true) { [weak self] _ in
            self?.startRecognitionTask()
          }
        }
      }
    }
  }

  private func beginAudioEngineIfNeeded() {
    guard !isAudioEngineRunning else { return }

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }

    audioEngine.prepare()
    do {
      try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
      try audioEngine.start()
      isAudioEngineRunning = true
    } catch {
      onError?("Couldn't start the microphone: \(error.localizedDescription)")
    }
  }

  private func startRecognitionTask() {
    guard let recognizer, recognizer.isAvailable else {
      onError?("On-device speech recognition isn't available for this language on this device.")
      return
    }

    task?.finish()

    let newRequest = SFSpeechAudioBufferRecognitionRequest()
    newRequest.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition {
      newRequest.requiresOnDeviceRecognition = true
    }
    request = newRequest

    task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
      guard let self else { return }
      if let result, result.isFinal {
        self.onTranscript?(result.bestTranscription.formattedString)
      }
      if let error {
        let nsError = error as NSError
        // Our own periodic restarts cancel the in-flight task/request, which
        // surfaces as a benign error here - don't treat that as a failure.
        if nsError.domain != "kAFAssistantErrorDomain" {
          self.onError?("Speech recognition hiccup: \(error.localizedDescription)")
        }
      }
    }
  }

  func stop() {
    restartTimer?.invalidate()
    restartTimer = nil
    task?.finish()
    task = nil
    request?.endAudio()
    request = nil
    if isAudioEngineRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
      isAudioEngineRunning = false
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
