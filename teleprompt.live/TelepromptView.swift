import SwiftUI
import AppAuth
import GTMSessionFetcherFull
import GoogleAPIClientForRESTCore
import GoogleAPIClientForREST_Docs
import GTMAppAuth

/// Where a script's text comes from.
enum ScriptSource {
  case googleDoc(id: String, authState: OIDAuthState)
  case text(title: String, body: String)
}

struct TelepromptView: View {
  private let source: ScriptSource

  @State private var documentContent: String = ""
  @State private var documentPieces: [String] = []
  @State private var docTitle: String?
  @State private var loadError: String?

  @State private var timer: Timer?
  @State private var scrollOffset: CGFloat = 0.0
  @State private var isScrolling: Bool = false
  /// Index into `documentPieces` of the line speech last matched.
  @State private var scrollAnchor: Int? = nil
  @State private var isListening: Bool = false

  private var matcher = StringMatcher()

  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @State private var scrollViewProxy: ScrollViewProxy? = nil

  private let service = GTLRDocsService()

  /// Stored script to show immediately and to update after a Google Doc
  /// load (feeds the grid preview and makes reopening instant/offline).
  private let cache: CachedDocument?

  init(source: ScriptSource, cache: CachedDocument? = nil) {
    self.source = source
    self.cache = cache
    if case .googleDoc(_, let authState) = source {
      self.service.authorizer = AuthSession(authState: authState)
    }
  }

  private var isGoogleDoc: Bool {
    if case .googleDoc = source { return true }
    return false
  }

  var body: some View {
    VStack(spacing: 0) {
      if let message = loadError ?? appDelegate.transcriptionError {
        Text(message)
          .font(.footnote)
          .foregroundColor(.white)
          .padding(8)
          .frame(maxWidth: .infinity)
          .background(Color.red.opacity(0.85))
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack {
            // Identify lines by position, not text: scripts often repeat a
            // line ("Thank you."), and duplicate ids break ForEach/scrollTo.
            ForEach(Array(documentPieces.enumerated()), id: \.offset) { i, item in
              Text(item)
                .background(Color.black)
                .foregroundColor(Color.white)
                .font(.system(size: 30))
                .id(i)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
          }
          .id("documentContent")
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .onAppear {
            self.scrollViewProxy = proxy
          }
          .onTapGesture {
            toggleScrolling(proxy: proxy)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .id("scrollViewReader")
      .navigationTitle(docTitle ?? "Loading…")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isGoogleDoc {
          Button(action: loadDoc) {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("Reload from Google Docs")
        }
      }
    }
    .onAppear(perform: loadDoc)
    .onChange(of: appDelegate.lastTranscript) {
      if let transcript = appDelegate.lastTranscript {
        self.handleLastTranscript(transcript: transcript)
      }
    }
    .onDisappear {
      stopScrolling()
      appDelegate.stopAnalyzingAudio()
      isListening = false
    }
  }

  private func toggleScrolling(proxy: ScrollViewProxy) {
    if isScrolling {
      stopScrolling()
    } else {
      startScrolling(proxy: proxy)
    }
  }

  private func startScrolling(proxy: ScrollViewProxy) {
    guard timer == nil else { return }
    let scrollSpeed: TimeInterval = 0.1
    let scrollStep: CGFloat = 0.0001 // Adjust this value to change the scroll step

    isScrolling = true
    self.timer = Timer.scheduledTimer(withTimeInterval: scrollSpeed, repeats: true) { _ in
      withAnimation {
        self.scrollOffset += scrollStep
        if let anchor = self.scrollAnchor {
          proxy.scrollTo(anchor, anchor: UnitPoint(x: 0, y: self.scrollOffset))
        } else {
          proxy.scrollTo("documentContent", anchor: UnitPoint(x: 0, y: self.scrollOffset))
        }
      }
    }
  }

  private func stopScrolling() {
    self.timer?.invalidate()
    self.timer = nil
    isScrolling = false
  }

  private func loadDoc() {
    switch source {
    case .googleDoc(let id, _):
      if documentPieces.isEmpty, let cached = cache?.body, !cached.isEmpty {
        docTitle = cache?.title
        applyContent(cached)
      }
      fetchDocumentContent(documentId: id)
    case .text(let title, let body):
      docTitle = title
      applyContent(body)
    }
  }

  private func applyContent(_ content: String) {
    documentContent = content
    documentPieces = splitStringIntoSentences(text: content)

    #if DEBUG
    // Demo recordings shouldn't trigger mic/speech permission prompts.
    if ProcessInfo.processInfo.arguments.contains("-UIDemoZoom") { return }
    #endif
    if !isListening {
      appDelegate.startAnalyzingAudio()
      isListening = true
    }
  }

  private func fetchDocumentContent(documentId: String) {
    let query = GTLRDocsQuery_DocumentsGet.query(withDocumentId: documentId)

    service.executeQuery(query) { (ticket, document, error) in
      if let error = error {
        DispatchQueue.main.async {
          self.loadError = "Couldn't load the Google Doc: \(error.localizedDescription)"
        }
        return
      }

      guard let document = document as? GTLRDocs_Document else {
        DispatchQueue.main.async { self.loadError = "Google Doc not found." }
        return
      }

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
        self.loadError = nil
        self.docTitle = document.title
        if content != self.documentContent {
          self.applyContent(content)
        }
        if let cache = self.cache {
          cache.body = content
          if let title = document.title { cache.title = title }
          cache.lastFetchedTimestamp = Date()
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
    var consumed = 0
    for result in results {
      // Text skipped between matches (e.g. a line with no punctuation that
      // ends in a newline) would otherwise be silently dropped.
      if result.range.location > consumed {
        sentences.append(nsString.substring(with: NSRange(location: consumed, length: result.range.location - consumed)))
      }
      sentences.append(nsString.substring(with: result.range))
      consumed = result.range.location + result.range.length
    }
    // Trailing text with no final punctuation (common in pasted scripts).
    if consumed < nsString.length {
      sentences.append(nsString.substring(from: consumed))
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
    guard !documentPieces.isEmpty, !transcript.isEmpty else { return }

    let (bestMatch, bestIndex, maxSimilarity) = matcher.findBestMatch(transcription: transcript, sentences: documentPieces)
    if bestMatch != nil && bestIndex >= 0 && maxSimilarity > 0.6 {
      scrollAnchor = bestIndex
      scrollOffset = 0
    }

    if !isScrolling, let proxy = scrollViewProxy {
      startScrolling(proxy: proxy)
    }
  }

}
