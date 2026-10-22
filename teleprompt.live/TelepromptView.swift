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

/// Layout measurements the scroller needs but rendering doesn't, kept out
/// of observation so recording them never re-renders the script.
@Observable
final class ScriptLayout {
  @ObservationIgnored var sentenceFrames: [Int: CGRect] = [:]
  @ObservationIgnored var lineHeight: CGFloat = 38
}

struct TelepromptView: View {
  private let source: ScriptSource

  @State private var documentContent: String = ""
  @State private var docTitle: String?
  @State private var loadError: String?
  @State private var isListening: Bool = false

  @State private var tracker = ScriptTracker()
  @State private var layout = ScriptLayout()
  @State private var position = ScrollPosition(y: 0)
  @State private var viewportHeight: CGFloat = 0
  @State private var contentOffset: CGFloat = 0
  /// Auto-follow pauses while (and shortly after) the user drags.
  @State private var userScrolledAt: Date?
  @State private var isUserScrolling = false
  /// Smooth mode's own notion of the offset, so per-frame motion doesn't
  /// round-trip through scroll geometry.
  @State private var smoothY: CGFloat?
  @State private var ticker = FrameTicker()

  @AppStorage("smoothScroll") private var smoothScrollSetting = false
  /// DEBUG demos can force smooth mode without changing the saved setting.
  @State private var forceSmooth = false
  private var smoothScroll: Bool { smoothScrollSetting || forceSmooth }
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate

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
      ScrollView {
        ScriptTextView(tracker: tracker, layout: layout, verticalInset: viewportHeight / 2)
      }
      .scrollPosition($position)
      .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
        ScrollMetrics(offset: geo.contentOffset.y, viewport: geo.containerSize.height)
      } action: { _, metrics in
        contentOffset = metrics.offset
        viewportHeight = metrics.viewport
      }
      .onScrollPhaseChange { _, phase in
        isUserScrolling = phase == .interacting || phase == .decelerating
        if phase == .interacting || phase == .decelerating {
          userScrolledAt = Date()
          smoothY = nil
        }
      }
      .background(Color.black)
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
        tracker.update(transcript: transcript)
      }
    }
    .onChange(of: focusLineKey) { followFocus() }
    .onChange(of: viewportHeight) { followFocus(animated: false) }
    .onChange(of: smoothScroll, initial: true) { configureTicker() }
    .onDisappear {
      ticker.stop()
      appDelegate.stopAnalyzingAudio()
      isListening = false
    }
    #if DEBUG
    .task(id: documentContent) { await runDemoIfRequested() }
    #endif
  }

  // MARK: - Following the speaker

  private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var viewport: CGFloat
  }

  /// Changes when the line holding the next word changes.
  private var focusLineKey: Int {
    guard let word = tracker.focusWord else { return -1 }
    return Int(focusLineY(for: word) ?? -1)
  }

  private var autoFollowPaused: Bool {
    if isUserScrolling { return true }
    if let at = userScrolledAt, Date().timeIntervalSince(at) < 2 { return true }
    return false
  }

  /// Center (content y) of the line holding `word`, estimated from the
  /// word's character offset within its sentence.
  private func focusLineY(for word: Int) -> CGFloat? {
    let doc = tracker.document
    guard word >= 0, word < doc.words.count else { return nil }
    let w = doc.words[word]
    guard let frame = layout.sentenceFrames[w.sentence], frame.height > 0 else { return nil }
    let text = doc.sentences[w.sentence].text
    let fraction = Double(text.distance(from: text.startIndex, to: w.range.lowerBound)) / Double(max(text.count, 1))
    let lines = max(1, (frame.height / layout.lineHeight).rounded())
    let line = min(lines - 1, (fraction * lines).rounded(.down))
    return frame.minY + (line + 0.5) * frame.height / lines
  }

  private func centeredOffset(for word: Int) -> CGFloat? {
    guard viewportHeight > 0, let y = focusLineY(for: word) else { return nil }
    return max(0, y - viewportHeight / 2)
  }

  /// Snap mode: ease the current line to the middle when it changes.
  private func followFocus(animated: Bool = true) {
    guard !smoothScroll, !autoFollowPaused,
          let word = tracker.focusWord, let target = centeredOffset(for: word) else { return }
    if animated {
      withAnimation(.smooth(duration: 0.6)) { position.scrollTo(y: target) }
    } else {
      position.scrollTo(y: target)
    }
  }

  private func configureTicker() {
    if smoothScroll {
      ticker.start { dt in smoothStep(dt) }
    } else {
      ticker.stop()
      smoothY = nil
      followFocus()
    }
  }

  /// Smooth mode: move at the speaker's pace (words/sec × points per word
  /// around the current line), corrected toward keeping that line
  /// centered. Never scrolls backward; waits if it gets ahead.
  private func smoothStep(_ dt: CFTimeInterval) {
    guard !autoFollowPaused, let word = tracker.focusWord,
          let target = centeredOffset(for: word) else { return }
    var y = smoothY ?? contentOffset
    let doc = tracker.document
    let sentence = doc.words[word].sentence
    let wordCount = max(doc.sentences[sentence].wordRange.count, 1)
    let pointsPerWord = (layout.sentenceFrames[sentence]?.height ?? layout.lineHeight) / CGFloat(wordCount)
    let pace = CGFloat(tracker.currentWordsPerSecond()) * pointsPerWord
    let error = target - y
    var velocity = pace + 1.5 * error
    if error < -1.5 * layout.lineHeight { velocity = 0 }
    velocity = min(max(velocity, 0), 2000)
    guard velocity > 0.5 else { return }
    y += velocity * CGFloat(dt)
    smoothY = y
    position.scrollTo(y: y)
  }

  // MARK: - Loading

  private func loadDoc() {
    switch source {
    case .googleDoc(let id, _):
      if documentContent.isEmpty, let cached = cache?.body, !cached.isEmpty {
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
    tracker.reset(document: ScriptDocument(text: content))
    layout.sentenceFrames = [:]

    #if DEBUG
    // Demo recordings shouldn't trigger mic/speech permission prompts.
    if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-UIDemo") }) { return }
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

  // MARK: - Demo

  #if DEBUG
  /// `-UIDemoTranscript`: plays a synthetic reading of the script into the
  /// tracker (one sentence skipped, one word misread, a short ad-lib) for
  /// simulator screenshots. `-UIDemoSmooth` turns on smooth scroll.
  private func runDemoIfRequested() async {
    let args = ProcessInfo.processInfo.arguments
    guard args.contains("-UIDemoTranscript"), !documentContent.isEmpty else { return }
    if args.contains("-UIDemoSmooth") { forceSmooth = true }
    let doc = tracker.document
    try? await Task.sleep(for: .seconds(1.5))
    for sentence in doc.sentences.indices {
      if sentence == 3 { continue }  // skipped
      var segment: [String] = []
      for w in doc.sentences[sentence].wordRange {
        let word = doc.words[w]
        var spoken = String(doc.sentences[sentence].text[word.range])
        if w == 20 { spoken = "student" }  // misread
        segment.append(spoken)
        tracker.update(transcript: segment.suffix(14).joined(separator: " "))
        try? await Task.sleep(for: .milliseconds(380))
        if Task.isCancelled { return }
      }
      if sentence == 5 {
        tracker.update(transcript: "okay where was I")
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
  #endif
}

/// The script, colored by progress. A separate view so per-frame scroll
/// updates in the parent don't rebuild every sentence.
private struct ScriptTextView: View {
  let tracker: ScriptTracker
  let layout: ScriptLayout
  let verticalInset: CGFloat

  static let fontSize: CGFloat = 32
  static let sentenceSpacing: CGFloat = 18
  static let font = Font.system(size: fontSize, weight: .medium)
  static let said = Color.white.opacity(0.35)
  static let highlight = Color(red: 1.0, green: 0.82, blue: 0.3)

  var body: some View {
    let doc = tracker.document
    let current = tracker.currentSentence
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(doc.paragraphs.enumerated()), id: \.offset) { p, sentences in
        VStack(alignment: .leading, spacing: Self.sentenceSpacing) {
          ForEach(Array(sentences), id: \.self) { s in
            Text(attributed(sentence: s, current: current))
              .font(Self.font)
              .lineHeight(.tight)
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("script")) } action: {
                layout.sentenceFrames[s] = $0
              }
          }
        }
        // An extra line between paragraphs.
        .padding(.bottom, p == doc.paragraphs.count - 1 ? 0 : layout.lineHeight + Self.sentenceSpacing)
      }
    }
    .padding(.horizontal, 28)
    .frame(maxWidth: 820, alignment: .leading)
    .frame(maxWidth: .infinity)
    .padding(.vertical, verticalInset)
    .background(alignment: .topLeading) {
      // Measures one line at the script's font and line height.
      Text("Ag").font(Self.font).lineHeight(.tight).hidden()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { layout.lineHeight = $0 }
    }
    .coordinateSpace(.named("script"))
  }

  /// Said sentences are gray. In the current sentence, heard words are
  /// highlighted (with the punctuation that follows them). Everything else,
  /// including skipped sentences, is plain white.
  private func attributed(sentence s: Int, current: Int?) -> AttributedString {
    var result = colored(sentence: s, current: current)
    // Keep em dashes on the line with the word before them.
    for range in result.characters.ranges(of: ["—"]).reversed() {
      result.characters.insert("\u{2060}", at: range.lowerBound)
    }
    return result
  }

  private func colored(sentence s: Int, current: Int?) -> AttributedString {
    let doc = tracker.document
    let sentence = doc.sentences[s]
    let isCurrent = s == current
    if !isCurrent {
      var text = AttributedString(sentence.text)
      text.foregroundColor = tracker.isSaid(sentence: s) ? Self.said : .white
      return text
    }
    var result = AttributedString()
    let text = sentence.text
    var index = text.startIndex
    let wordIndices = Array(sentence.wordRange)
    if let first = wordIndices.first {
      var lead = AttributedString(text[index..<doc.words[first].range.lowerBound])
      lead.foregroundColor = .white
      result += lead
      index = doc.words[first].range.lowerBound
    }
    for (k, w) in wordIndices.enumerated() {
      let end = k + 1 < wordIndices.count ? doc.words[wordIndices[k + 1]].range.lowerBound : text.endIndex
      var piece = AttributedString(text[index..<end])
      piece.foregroundColor = tracker.heard[w] ? Self.highlight : .white
      result += piece
      index = end
    }
    if index < text.endIndex {
      var tail = AttributedString(text[index...])
      tail.foregroundColor = .white
      result += tail
    }
    return result
  }
}

/// Calls back once per display frame with the elapsed time.
final class FrameTicker {
  private var link: CADisplayLink?
  private var last: CFTimeInterval = 0
  private var onFrame: ((CFTimeInterval) -> Void)?

  func start(_ onFrame: @escaping (CFTimeInterval) -> Void) {
    stop()
    self.onFrame = onFrame
    last = 0
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func stop() {
    link?.invalidate()
    link = nil
    onFrame = nil
  }

  @objc private func tick(_ link: CADisplayLink) {
    let dt = last == 0 ? 0 : min(link.timestamp - last, 0.1)
    last = link.timestamp
    if dt > 0 { onFrame?(dt) }
  }
}
