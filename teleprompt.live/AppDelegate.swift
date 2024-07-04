import UIKit
import AppAuth
import Starscream
import AVFoundation
import SwiftUI

class TelepromptAppDelegate: UIResponder, UIApplicationDelegate, ObservableObject, WebSocketDelegate {
  
  
  var window: UIWindow?
  var currentAuthorizationFlow: OIDExternalUserAgentSession?
  
  @Published var lastTranscript: String?
  
  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    print("application open \(url)")
    if let authorizationFlow = currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
      currentAuthorizationFlow = nil
      return true
    }
    return false
  }
  
  private let apiKey = "Token 589eebf8f97620ef9a6d772797b209138fb93511"
  private let audioEngine = AVAudioEngine()
  
  private lazy var socket: WebSocket = {
    let url = URL(string: "wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=48000&channels=1&model=nova&smart_format=true&filler_words=true&interim_results=true")!
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
    return WebSocket(request: urlRequest)
  }()
  
  private let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()
  
  
  func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
    switch event {
    case .text(let text):
      let jsonData = Data(text.utf8)
      // TODO this crashes in the background
      let response = try! jsonDecoder.decode(DeepgramResponse.self, from: jsonData)
      if (response.isFinal == false) {
        print("> \(response.channel.alternatives.first!.transcript)")
        return
      }
      let transcript = response.channel.alternatives.first!.transcript
      
      print(response.channel.alternatives)

      DispatchQueue.main.async {
        self.lastTranscript = transcript
      }
    case .error(let error):
      print(error ?? "")
    default:
      break
    }
  }
  
  func startAnalyzingAudio() {
    socket.delegate = self
    socket.connect()
    
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.inputFormat(forBus: 0)
    let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount, interleaved: true)
    let converterNode = AVAudioMixerNode()
    let sinkNode = AVAudioMixerNode()
    
    audioEngine.attach(converterNode)
    audioEngine.attach(sinkNode)
    
    converterNode.installTap(onBus: 0, bufferSize: 1024, format: converterNode.outputFormat(forBus: 0)) { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in
      if let data = self.toNSData(buffer: buffer) {
        self.socket.write(data: data)
      }
    }
    
    audioEngine.connect(inputNode, to: converterNode, format: inputFormat)
    audioEngine.connect(converterNode, to: sinkNode, format: outputFormat)
    audioEngine.prepare()
    
    do {
      try AVAudioSession.sharedInstance().setCategory(.record)
      try audioEngine.start()
    } catch {
      print(error)
    }
  }
  
  private func toNSData(buffer: AVAudioPCMBuffer) -> Data? {
    let audioBuffer = buffer.audioBufferList.pointee.mBuffers
    return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
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
