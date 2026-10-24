import Foundation
import AVFoundation
import Starscream

/// Alternate engine: streams raw audio to Deepgram's cloud API. Requires
/// network connectivity and a configured API key (see Config/Secrets.xcconfig).
final class DeepgramTranscriptionEngine: NSObject, TranscriptionEngine, WebSocketDelegate {
  var onTranscript: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private let audioEngine = AVAudioEngine()
  private var socket: Starscream.WebSocket?
  private var isAudioEngineRunning = false

  private var apiKey: String {
    (Bundle.main.object(forInfoDictionaryKey: "DeepgramAPIKey") as? String) ?? ""
  }

  private let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  func start() {
    guard !apiKey.isEmpty else {
      onError?("No Deepgram API key configured. Copy Config/Secrets.xcconfig.example to Config/Secrets.xcconfig and fill in a key, or switch to the on-device engine.")
      return
    }

    AVAudioApplication.requestRecordPermission { [weak self] granted in
      guard let self else { return }
      guard granted else {
        self.onError?("Microphone access is off. Enable it in Settings > Privacy & Security > Microphone to use the teleprompter.")
        return
      }
      DispatchQueue.main.async {
        self.connectAndStartAudio()
      }
    }
  }

  private func connectAndStartAudio() {
    guard let url = URL(string: "wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=48000&channels=1&model=nova&smart_format=true&filler_words=true&interim_results=true") else {
      return
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue("Token " + apiKey, forHTTPHeaderField: "Authorization")
    let socket = Starscream.WebSocket(request: urlRequest)
    socket.delegate = self
    socket.connect()
    self.socket = socket

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.inputFormat(forBus: 0)
    let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount, interleaved: true)
    let converterNode = AVAudioMixerNode()
    let sinkNode = AVAudioMixerNode()

    audioEngine.attach(converterNode)
    audioEngine.attach(sinkNode)

    converterNode.installTap(onBus: 0, bufferSize: 1024, format: converterNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
      if let data = self?.toNSData(buffer: buffer) {
        self?.socket?.write(data: data)
      }
    }

    audioEngine.connect(inputNode, to: converterNode, format: inputFormat)
    audioEngine.connect(converterNode, to: sinkNode, format: outputFormat)
    audioEngine.prepare()

    do {
      try AVAudioSession.sharedInstance().setCategory(.record)
      try audioEngine.start()
      isAudioEngineRunning = true
    } catch {
      onError?("Couldn't start the microphone: \(error.localizedDescription)")
    }
  }

  func stop() {
    socket?.disconnect()
    socket = nil
    if isAudioEngineRunning {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
      isAudioEngineRunning = false
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func toNSData(buffer: AVAudioPCMBuffer) -> Data? {
    let audioBuffer = buffer.audioBufferList.pointee.mBuffers
    return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
  }

  func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
    switch event {
    case .text(let text):
      let jsonData = Data(text.utf8)
      guard let response = try? jsonDecoder.decode(DeepgramResponse.self, from: jsonData) else { return }
      guard response.isFinal, let transcript = response.channel.alternatives.first?.transcript, !transcript.isEmpty else { return }
      onTranscript?(transcript)
    case .error(let error):
      onError?("Deepgram connection error: \(error?.localizedDescription ?? "unknown")")
    default:
      break
    }
  }
}

struct DeepgramResponse: Codable {
  let isFinal: Bool
  let channel: Channel

  struct Channel: Codable {
    let alternatives: [Alternatives]
  }

  struct Alternatives: Codable {
    let transcript: String
  }
}
