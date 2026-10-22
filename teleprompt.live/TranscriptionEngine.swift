import Foundation

/// Abstraction over a live speech-to-text source. Both the on-device and
/// cloud (Deepgram) engines conform to this so the rest of the app doesn't
/// care which one is active.
protocol TranscriptionEngine: AnyObject {
  /// Called on an arbitrary queue with transcript text: finalized chunks,
  /// and (for engines that support it) in-progress text that may be revised.
  var onTranscript: ((String) -> Void)? { get set }
  /// Called on an arbitrary queue with a user-facing error description
  /// (permission denied, missing config, engine failure, etc).
  var onError: ((String) -> Void)? { get set }

  func start()
  func stop()
}

enum TranscriptionEngineKind: String, CaseIterable, Identifiable {
  case onDevice
  case deepgram

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .onDevice: return "On Device"
    case .deepgram: return "Deepgram"
    }
  }
}
