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
  @ObservationIgnored var flywheel = Flywheel()
  /// Set when the offset changed outside the flywheel (user scroll, mode
  /// switch); the next step starts from the real offset at rest.
  @ObservationIgnored var flywheelNeedsSync = true

  /// Average scroll distance per script word (content height / words),
  /// so pace doesn't jump between short and long sentences.
  func pointsPerWord(wordCount: Int, sentenceCount: Int) -> CGFloat? {
    guard wordCount > 0, let first = sentenceFrames[0], let last = sentenceFrames[sentenceCount - 1] else { return nil }
    return (last.maxY - first.minY) / CGFloat(wordCount)
  }
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
  @State private var ticker = FrameTicker()

  @AppStorage("smoothScroll") private var smoothScrollSetting = true
  @AppStorage("lightFunctionWords") private var lightFunctionWords = true
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
        ScriptTextView(tracker: tracker, layout: layout, verticalInset: viewportHeight / 2,
                       lightFunctionWords: lightFunctionWords)
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
          layout.flywheelNeedsSync = true
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
    layout.flywheelNeedsSync = true
    if smoothScroll {
      ticker.start { dt in smoothStep(dt) }
    } else {
      ticker.stop()
      followFocus()
    }
  }

  /// Smooth mode: a flywheel with friction (see `Flywheel`). Speaking spins
  /// it toward your average pace; pausing lets it coast to a stop, with a
  /// weak pull toward centering the next line.
  private func smoothStep(_ dt: CFTimeInterval) {
    guard !autoFollowPaused, let word = tracker.focusWord,
          let target = centeredOffset(for: word) else { return }
    if layout.flywheelNeedsSync {
      layout.flywheel.reset(position: contentOffset)
      layout.flywheelNeedsSync = false
    }
    let doc = tracker.document
    let pointsPerWord = layout.pointsPerWord(wordCount: doc.words.count, sentenceCount: doc.sentences.count) ?? layout.lineHeight / 6
    let speaking = tracker.lastAdvance.map { Date().timeIntervalSince($0) < 1.2 } ?? false
    let before = layout.flywheel.position
    layout.flywheel.step(dt: dt, target: target,
                         speakingPace: tracker.wordsPerSecond * pointsPerWord,
                         speaking: speaking)
    // Skip sub-pixel updates so a resting flywheel doesn't re-render.
    guard abs(layout.flywheel.position - before) > 0.05 else { return }
    position.scrollTo(y: layout.flywheel.position)
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
  /// Set function words (the, of, and, it, would…) in a lighter weight.
  let lightFunctionWords: Bool

  static let fontSize: CGFloat = 32
  static let sentenceSpacing: CGFloat = 18
  static let font = Font.system(size: fontSize, weight: .medium)
  static let lightFont = Font.system(size: fontSize, weight: .light)
  static let horizontalPadding: CGFloat = 28

  /// Longest line, in characters. Print guidance is 45–75 (66 ideal); a
  /// prompter is read aloud at a glance, often near a camera, so use the
  /// short end: less eye travel on camera and easier returns to the next
  /// line. Narrow screens (phones in portrait) are already well under it.
  static let maxCharactersPerLine = 45

  /// `maxCharactersPerLine` in points, from the average character width
  /// of English prose at the script font.
  static let maxLineWidth: CGFloat = {
    let sample = "Being told I would be expected to talk here, I inquired what sort of talk I ought to make. They said it should be something suitable to youth."
    let uiFont = UIFont.systemFont(ofSize: fontSize, weight: .medium)
    let width = (sample as NSString).size(withAttributes: [.font: uiFont]).width
    return ceil(width / CGFloat(sample.count) * CGFloat(maxCharactersPerLine))
  }()

  var body: some View {
    let doc = tracker.document
    let fade = FadeState(tracker: tracker)
    let now = Date()
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(doc.paragraphs.enumerated()), id: \.offset) { p, sentences in
        VStack(alignment: .leading, spacing: Self.sentenceSpacing) {
          ForEach(Array(sentences), id: \.self) { s in
            // Re-render at 60 fps only while one of this sentence's fades
            // is running, then stop.
            TimelineView(.explicit(fade.frameDates(sentence: s, document: doc, now: now))) { context in
              Text(attributed(sentence: s, fade: fade, at: context.date))
            }
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
    .padding(.horizontal, Self.horizontalPadding)
    .frame(maxWidth: Self.maxLineWidth + 2 * Self.horizontalPadding, alignment: .leading)
    .frame(maxWidth: .infinity)
    .padding(.vertical, verticalInset)
    .background(alignment: .topLeading) {
      // Measures one line at the script's font and line height.
      Text("Ag").font(Self.font).lineHeight(.tight).hidden()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { layout.lineHeight = $0 }
    }
    .coordinateSpace(.named("script"))
  }

  // MARK: - Fade

  /// Said words drop to 80% at once, then ease to 40% over 333 ms.
  static let fadeStart = 0.8
  static let fadeEnd = 0.4
  static let fadeDuration: TimeInterval = 0.333

  /// Opacity `t` seconds after a word was said.
  static func saidOpacity(after t: TimeInterval) -> Double {
    let x = min(max(t / fadeDuration, 0), 1)
    let eased = 1 - (1 - x) * (1 - x)
    return fadeStart - (fadeStart - fadeEnd) * eased
  }

  /// Snapshot of what the fade needs, taken once per render.
  struct FadeState {
    let cursor: Int
    let heardAt: [Date?]
    let sentenceSaidAt: [Date?]
    let paragraphDoneAt: [Date?]

    init(tracker: ScriptTracker) {
      cursor = tracker.cursor
      heardAt = tracker.heardAt
      sentenceSaidAt = tracker.sentenceSaidAt
      paragraphDoneAt = tracker.paragraphDoneAt
    }

    /// When a word's fade started, and whether it's a full (said) fade or a
    /// half (missed, paragraph finished) fade. Nil: still white.
    func fadeStart(word w: Int, sentence s: Int, paragraph p: Int) -> (Date, half: Bool)? {
      guard w <= cursor else { return nil }
      if let t = heardAt[w] ?? sentenceSaidAt[s] { return (t, false) }
      if let t = paragraphDoneAt[p] { return (t, true) }
      return nil
    }

    /// 60 fps dates from now until the sentence's newest fade finishes.
    func frameDates(sentence s: Int, document doc: ScriptDocument, now: Date) -> [Date] {
      let sentence = doc.sentences[s]
      var latest: Date?
      for w in sentence.wordRange {
        if let (t, _) = fadeStart(word: w, sentence: s, paragraph: sentence.paragraph),
           latest.map({ t > $0 }) ?? true {
          latest = t
        }
      }
      guard let latest else { return [] }
      let end = latest.addingTimeInterval(ScriptTextView.fadeDuration + 0.02)
      guard end > now else { return [] }
      return Array(stride(from: now, through: end, by: 1.0 / 60))
    }
  }

  static func opacity(word w: Int, sentence s: Int, paragraph p: Int, fade: FadeState, at date: Date) -> Double {
    guard let (start, half) = fade.fadeStart(word: w, sentence: s, paragraph: p) else { return 1 }
    let full = saidOpacity(after: date.timeIntervalSince(start))
    return half ? 1 - (1 - full) / 2 : full
  }

  private func attributed(sentence s: Int, fade: FadeState, at date: Date) -> AttributedString {
    var result = styled(sentence: s, fade: fade, at: date)
    // Keep em dashes on the line with the word before them.
    for range in result.characters.ranges(of: ["—"]).reversed() {
      result.characters.insert("\u{2060}", at: range.lowerBound)
    }
    return result
  }

  /// Each word is styled along with the punctuation/space after it; any
  /// text before the first word takes the first word's style.
  private func styled(sentence s: Int, fade: FadeState, at date: Date) -> AttributedString {
    let doc = tracker.document
    let sentence = doc.sentences[s]
    let text = sentence.text
    let wordIndices = Array(sentence.wordRange)
    guard !wordIndices.isEmpty else {
      var plain = AttributedString(text)
      plain.foregroundColor = .white
      return plain
    }
    var result = AttributedString()
    var index = text.startIndex
    for (k, w) in wordIndices.enumerated() {
      let end = k + 1 < wordIndices.count ? doc.words[wordIndices[k + 1]].range.lowerBound : text.endIndex
      var piece = AttributedString(text[index..<end])
      let o = Self.opacity(word: w, sentence: s, paragraph: sentence.paragraph, fade: fade, at: date)
      piece.foregroundColor = o >= 1 ? .white : Color.white.opacity(o)
      if lightFunctionWords && doc.words[w].isFunctionWord {
        piece.font = Self.lightFont
      }
      result += piece
      index = end
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
