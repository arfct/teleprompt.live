import SwiftUI
import AppAuth
import GTMSessionFetcherFull
import GoogleAPIClientForRESTCore
import GoogleAPIClientForREST_Docs
import GTMAppAuth

extension String {
  func hashValue() -> Int {
    var hasher = Hasher()
    hasher.combine(self)
    return hasher.finalize()
  }
}

struct TelepromptView: View {
  @State private var authState: OIDAuthState
  @State private var googleDocId: String

  @State private var documentContent: String = ""
  @State private var documentPieces: [String] = []
  @State private var docTitle: String?
  
  @State private var timer: Timer?
  @State private var scrollOffset: CGFloat = 0.0
  @State private var contentHeight: CGFloat = 0.0
  @State private var scrollViewHeight: CGFloat = 0.0
  @State private var isScrolling: Bool = false
  @State private var scrollAnchor: Int? = nil
  @State private var isListening: Bool = false
  
  private var matcher = StringMatcher()
  
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @State private var scrollViewProxy: ScrollViewProxy? = nil
  
  
  private let service = GTLRDocsService()
  
  init(googleDocId: String, authState: OIDAuthState) {
    self.googleDocId = googleDocId
    self.authState = authState
    self.service.authorizer = AuthSession(authState: authState)
  }
  
  var body: some View {
    VStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack {
            ForEach(Array(documentPieces.enumerated()), id: \.element) { i, item in
              Text(item)
                .background(Color.black)
                .foregroundColor(Color.white)
                .font(.system(size: 30))
                .id(item.hashValue())
                .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
            }
          }
          .id("documentContent")
          .onAppear() {
            self.scrollViewProxy = proxy
          }
          .onTapGesture {
            toggleScrolling(proxy:proxy)
          }
          .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        }
        .background(Color.black)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
      }
      .id("scrollViewReader")
      .toolbar {
        Button(action: loadDoc) {
          // TODO make this a refresh icon
          Text(docTitle ?? "Loading...")
        }
      }
    }
    .onAppear(perform: loadDoc)
    .onChange(of: appDelegate.lastTranscript) {
      if (appDelegate.lastTranscript != nil) {
        self.handleLastTranscript(transcript: appDelegate.lastTranscript!)
      }
    }
    .onDisappear {
      appDelegate.stopAnalyzingAudio()
      isListening = false
    }
  }
  
  private func toggleScrolling(proxy: ScrollViewProxy) {
    if isScrolling {
      stopScrolling()
    } else {
      startScrolling(proxy:proxy)
    }
    isScrolling.toggle()
  }
  
  private func startScrolling(proxy: ScrollViewProxy) {
    let scrollSpeed: TimeInterval = 0.1
    let scrollStep: CGFloat = 0.0001 // Adjust this value to change the scroll step
    
    self.timer = Timer.scheduledTimer(withTimeInterval: scrollSpeed, repeats: true) { _ in
      withAnimation() {
        self.scrollOffset += scrollStep
        if (self.scrollAnchor == nil) {
          proxy.scrollTo("documentContent", anchor: UnitPoint(x:0, y: self.scrollOffset))
        } else {
          proxy.scrollTo(self.scrollAnchor, anchor: UnitPoint(x:0, y: self.scrollOffset))
        }
      }
    }
  }
  
  private func stopScrolling() {
    self.timer?.invalidate()
    self.timer = nil
  }
  
  private func getRootViewController() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      return nil
    }
    return scene.windows.first?.rootViewController
  }
  
  private func loadDoc() {
    fetchDocumentContent(documentId: self.googleDocId)
  }

  private func fetchDocumentContent(documentId: String) {
    let query = GTLRDocsQuery_DocumentsGet.query(withDocumentId: documentId)
    
    service.executeQuery(query) { (ticket, document, error) in
      if let error = error {
        print("Error fetching document: \(error)")
        return
      }
      
      guard let document = document as? GTLRDocs_Document else {
        print("No document found")
        return
      }
      
      self.docTitle = document.title
      
      var content = ""
      if let elements = document.body?.content {
        for element in elements {
          if let paragraph = element.paragraph, let elements = paragraph.elements {
            for element in elements {
              if let textRun = element.textRun, let text = textRun.content {
                content += text
              }
            }
          }
        }
      }
      
      DispatchQueue.main.async {
        self.documentContent = content
        self.documentPieces = splitStringIntoSentences(text: content)
        
        if (!self.isListening) {
          appDelegate.startAnalyzingAudio()
          self.isListening = true
        }
      }
    }
  }
  
  func splitStringIntoSentences(text: String, maxSentenceLength: Int = 140) -> [String] {
    // Regular expression to match sentences, including those ending with punctuation inside quotes
    let regex = try! NSRegularExpression(pattern: "(.*?)([,.!?])(?:\\s|$)", options: [])
    let nsString = text as NSString
    let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
    
    var sentences = [String]()
    for result in results {
      let sentence = nsString.substring(with: result.range)
      sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    var result = [String]()
    
    for sentence in sentences {
      var trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
      while trimmedSentence.count > maxSentenceLength {
        if let spaceIndex = trimmedSentence.prefix(maxSentenceLength).lastIndex(of: " ") {
          let part = trimmedSentence.prefix(upTo: spaceIndex)
          result.append(String(part).trimmingCharacters(in: .whitespacesAndNewlines))
          trimmedSentence = String(trimmedSentence.suffix(from: trimmedSentence.index(after: spaceIndex)))
        } else {
          // If no space found, force split at maxSentenceLength
          let part = trimmedSentence.prefix(maxSentenceLength)
          result.append(String(part))
          trimmedSentence = String(trimmedSentence.suffix(from: trimmedSentence.index(trimmedSentence.startIndex, offsetBy: maxSentenceLength)))
        }
      }
      // Add the remaining part of the sentence
      if !trimmedSentence.isEmpty {
        result.append(trimmedSentence)
      }
    }
    
    return result
  }
  
  
  private func handleLastTranscript(transcript: String) {
    if !(self.documentPieces.isEmpty && transcript.count > 0) {
      
      let (bestMatch, bestIndex, maxSimilarity) = matcher.findBestMatch(transcription: transcript, sentences: self.documentPieces)
      let minHash = bestMatch?.hashValue()
      
      if (bestMatch != nil && maxSimilarity > 0.6) {
        DispatchQueue.main.async {
          scrollAnchor = minHash
          scrollOffset = 0
        }
      }
    }
    
    if (transcript.count > 0 && !isScrolling && self.scrollViewProxy != nil) {
      startScrolling(proxy: self.scrollViewProxy!)
    }
  }

}

