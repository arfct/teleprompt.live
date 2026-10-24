import UIKit
import AppAuth
import SwiftUI

class TelepromptAppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {

  var window: UIWindow?
  var currentAuthorizationFlow: OIDExternalUserAgentSession?

  @Published var lastTranscript: String?
  @Published var transcriptionError: String?

  @AppStorage("transcriptionEngine") var engineKindRaw: String = TranscriptionEngineKind.onDevice.rawValue

  private var engine: TranscriptionEngine?

  var selectedEngineKind: TranscriptionEngineKind {
    get { TranscriptionEngineKind(rawValue: engineKindRaw) ?? .onDevice }
    set { engineKindRaw = newValue.rawValue }
  }

  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    print("application open \(url)")
    if let authorizationFlow = currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
      currentAuthorizationFlow = nil
      return true
    }
    return false
  }

  func startAnalyzingAudio() {
    transcriptionError = nil

    let engine: TranscriptionEngine
    switch selectedEngineKind {
    case .onDevice:
      engine = SpeechAnalyzerTranscriptionEngine.isSupported
        ? SpeechAnalyzerTranscriptionEngine()
        : OnDeviceTranscriptionEngine()
    case .deepgram:
      engine = DeepgramTranscriptionEngine()
    }

    engine.onTranscript = { [weak self] transcript in
      DispatchQueue.main.async {
        self?.lastTranscript = transcript
      }
    }
    engine.onError = { [weak self] message in
      DispatchQueue.main.async {
        self?.transcriptionError = message
      }
    }

    self.engine = engine
    engine.start()
  }

  func stopAnalyzingAudio() {
    engine?.stop()
    engine = nil
  }
}
