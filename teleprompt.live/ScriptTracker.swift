import Foundation
import Observation

/// Follows a live transcript through a script, word by word.
///
/// Each update aligns the transcript's last few words against the script
/// near the current position (local alignment with fuzzy word matching),
/// and only moves the cursor when the evidence is strong enough for how
/// far it would move. Small forward moves are cheap; big jumps (skipped
/// sentences) and any rewind need more matched words and must repeat on
/// two consecutive updates. Otherwise the tracker holds and waits for the
/// speaker to come back into sync.
@Observable
final class ScriptTracker {
  private(set) var document: ScriptDocument
  /// Per script word: matched (or forgiven, between matches) at least once.
  private(set) var heard: [Bool]
  /// When each word was first heard (drives the fade).
  private(set) var heardAt: [Date?]
  /// When each sentence first passed `saidThreshold`.
  private(set) var sentenceSaidAt: [Date?]
  /// When the speaker first moved past each paragraph's last word.
  private(set) var paragraphDoneAt: [Date?]
  /// Index of the last word confirmed spoken; -1 before the first.
  private(set) var cursor: Int = -1
  /// Smoothed speaking speed while the speaker is making progress.
  private(set) var wordsPerSecond: Double = 0
  private(set) var lastAdvance: Date?

  /// Fraction of a sentence's words that must be heard to count as said.
  static let saidThreshold = 0.7

  @ObservationIgnored private var pending: (target: Int, hits: Int)?
  @ObservationIgnored private var samples: [(time: Date, cursor: Int)] = []

  init(document: ScriptDocument = .empty) {
    self.document = document
    self.heard = Array(repeating: false, count: document.words.count)
    self.heardAt = Array(repeating: nil, count: document.words.count)
    self.sentenceSaidAt = Array(repeating: nil, count: document.sentences.count)
    self.paragraphDoneAt = Array(repeating: nil, count: document.paragraphs.count)
  }

  func reset(document: ScriptDocument) {
    self.document = document
    heard = Array(repeating: false, count: document.words.count)
    heardAt = Array(repeating: nil, count: document.words.count)
    sentenceSaidAt = Array(repeating: nil, count: document.sentences.count)
    paragraphDoneAt = Array(repeating: nil, count: document.paragraphs.count)
    cursor = -1
    wordsPerSecond = 0
    lastAdvance = nil
    pending = nil
    samples = []
  }

  // MARK: - Derived state

  /// The next word the speaker is expected to say.
  var focusWord: Int? {
    document.words.isEmpty ? nil : min(cursor + 1, document.words.count - 1)
  }

  var currentSentence: Int? {
    focusWord.map { document.words[$0].sentence }
  }

  func heardFraction(sentence: Int) -> Double {
    let range = document.sentences[sentence].wordRange
    guard !range.isEmpty else { return 0 }
    return Double(range.filter { heard[$0] }.count) / Double(range.count)
  }

  func isSaid(sentence: Int) -> Bool {
    heardFraction(sentence: sentence) >= Self.saidThreshold
  }

  /// Speed with decay once the speaker stops making progress.
  func currentWordsPerSecond(at now: Date = Date()) -> Double {
    guard let lastAdvance else { return 0 }
    let idle = now.timeIntervalSince(lastAdvance)
    return idle < 2.5 ? wordsPerSecond : wordsPerSecond * exp(-(idle - 2.5) / 1.5)
  }

  // MARK: - Updates

  /// Feeds the latest transcript text (volatile or final). Returns true if
  /// the cursor or heard words changed.
  @discardableResult
  func update(transcript: String, at now: Date = Date()) -> Bool {
    let spoken = Array(ScriptDocument.normalizedWords(in: transcript).suffix(12))
    guard spoken.count >= 2, !document.words.isEmpty else { return false }

    let lo = max(0, cursor - 200)
    let hi = min(document.words.count, cursor + 1 + 600)
    let candidates = align(spoken, window: lo..<hi)

    // Rank every candidate, including "still here" (no move), so a weak
    // match elsewhere never beats a strong one at the current position.
    enum Kind { case hold, near, jump }
    var bestLocal: (c: Candidate, kind: Kind, rank: Double)?
    var bestJump: (c: Candidate, rank: Double)?
    for c in candidates {
      let delta = c.end - cursor
      let kind: Kind
      let required: Int
      switch delta {
      case ...(-4): kind = .jump; required = 5        // re-reading earlier text
      case -3...0: kind = .hold; required = 1
      case 1...15: kind = .near; required = 2
      case 16...40: kind = .near; required = 3
      default: kind = .jump; required = 5             // skipped ahead
      }
      guard c.matches >= required else { continue }
      let rank = c.score - 0.05 * Double(max(delta, 0)) - 0.3 * Double(max(-delta, 0))
      if kind == .jump {
        if bestJump == nil || rank > bestJump!.rank { bestJump = (c, rank) }
      } else if bestLocal == nil || rank > bestLocal!.rank {
        bestLocal = (c, kind, rank)
      }
    }

    // A jump must clearly beat staying local, then be confirmed by a later
    // update that has moved further along at the new spot.
    if let jump = bestJump, jump.rank > (bestLocal?.rank ?? 0) + 4 {
      if let p = pending, jump.c.end > p.target, jump.c.end - p.target <= 15 {
        pending = nil
        samples = []  // a jump isn't speaking speed
        return accept(jump.c, at: now, allowRewind: true)
      }
      if pending == nil || jump.c.end < pending!.target || jump.c.end - pending!.target > 15 {
        pending = (jump.c.end, 1)
      }
      return false
    }
    pending = nil
    guard let local = bestLocal else { return false }
    return accept(local.c, at: now)
  }

  private func accept(_ c: Candidate, at now: Date, allowRewind: Bool = false) -> Bool {
    var changed = false
    for i in c.start...c.end where !heard[i] {
      heard[i] = true
      heardAt[i] = now
      changed = true
    }
    let firstSentence = document.words[c.start].sentence
    let lastSentence = document.words[c.end].sentence
    for s in firstSentence...lastSentence where sentenceSaidAt[s] == nil && isSaid(sentence: s) {
      sentenceSaidAt[s] = now
    }
    if c.end > cursor || (allowRewind && c.end != cursor) {
      cursor = c.end
      lastAdvance = now
      recordSpeed(at: now)
      changed = true
    }
    for (p, range) in document.paragraphs.enumerated() where paragraphDoneAt[p] == nil {
      let lastWord = document.sentences[range.upperBound - 1].wordRange.upperBound - 1
      if lastWord < cursor { paragraphDoneAt[p] = now }
    }
    return changed
  }

  private func recordSpeed(at now: Date) {
    samples.append((now, cursor))
    samples.removeAll { now.timeIntervalSince($0.time) > 6 }
    guard let first = samples.first, samples.count >= 2 else { return }
    let span = now.timeIntervalSince(first.time)
    guard span >= 1 else { return }
    let instant = Double(cursor - first.cursor) / span
    guard instant >= 0 else { samples = [(now, cursor)]; return }
    wordsPerSecond = wordsPerSecond == 0 ? instant : wordsPerSecond * 0.7 + instant * 0.3
  }

  // MARK: - Alignment

  struct Candidate {
    /// Script word where the alignment ends (the newest spoken word).
    let end: Int
    /// First matched script word.
    let start: Int
    let matches: Int
    let score: Double
  }

  /// Smith–Waterman of `spoken` against script words in `window`. Returns
  /// one candidate per script position whose alignment ends with a match
  /// on the last or second-to-last spoken word (the last is often partial).
  func align(_ spoken: [String], window: Range<Int>) -> [Candidate] {
    let words = document.words
    let m = spoken.count, n = window.count
    guard m > 0, n > 0 else { return [] }
    let gap = -1.0, mismatch = -1.0

    struct Cell { var score = 0.0; var matches = 0; var start = -1; var endsWithMatch = false }
    var prev = [Cell](repeating: Cell(), count: n + 1)
    var cur = prev
    var best: [Int: Candidate] = [:]

    for i in 1...m {
      cur[0] = Cell()
      let isLast = i == m
      for j in 1...n {
        let w = window.lowerBound + j - 1
        let sim = Self.similarity(spoken[i - 1], words[w].normalized, allowPrefix: isLast)
        var cell = Cell()
        // Diagonal: match or mismatch.
        let d = prev[j - 1]
        let diag = d.score + (sim > 0 ? 2 * sim : mismatch)
        if diag > cell.score {
          cell = Cell(score: diag,
                      matches: d.matches + (sim > 0 ? 1 : 0),
                      start: sim > 0 && d.start < 0 ? w : d.start,
                      endsWithMatch: sim > 0)
        }
        // Skip a spoken word (misheard/extra) or a script word (skipped).
        let up = prev[j].score + gap
        if up > cell.score { cell = Cell(score: up, matches: prev[j].matches, start: prev[j].start) }
        let left = cur[j - 1].score + gap
        if left > cell.score { cell = Cell(score: left, matches: cur[j - 1].matches, start: cur[j - 1].start) }
        cur[j] = cell

        if i >= m - 1, cell.endsWithMatch, cell.start >= 0 {
          let c = Candidate(end: w, start: cell.start, matches: cell.matches, score: cell.score)
          if best[w].map({ c.score > $0.score }) ?? true { best[w] = c }
        }
      }
      swap(&prev, &cur)
    }
    return Array(best.values)
  }

  private static let homophones: [Set<String>] = [
    ["to", "too", "two"], ["there", "their", "theyre"], ["your", "youre"],
    ["know", "no"], ["right", "write"], ["one", "won", "1"],
    ["for", "four", "4"], ["then", "than"], ["hear", "here"], ["by", "buy", "bye"],
  ]

  /// 0 = different; otherwise a similarity in (0, 1].
  static func similarity(_ a: String, _ b: String, allowPrefix: Bool) -> Double {
    if a == b { return 1 }
    if homophones.contains(where: { $0.contains(a) && $0.contains(b) }) { return 0.9 }
    // The newest spoken word is often cut off ("Al" for "always").
    if allowPrefix, a.count >= 2, b.hasPrefix(a) { return 0.7 }
    let longest = max(a.count, b.count)
    guard longest >= 4, abs(a.count - b.count) <= longest / 2 else { return 0 }
    let ratio = 1 - Double(levenshtein(Array(a.utf8), Array(b.utf8))) / Double(longest)
    return ratio >= 0.7 ? ratio : 0
  }

  private static func levenshtein(_ a: [UInt8], _ b: [UInt8]) -> Int {
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
      var diag = row[0]
      row[0] = i
      for j in 1...max(b.count, 1) where !b.isEmpty {
        let tmp = row[j]
        row[j] = a[i - 1] == b[j - 1] ? diag : min(diag, row[j], row[j - 1]) + 1
        diag = tmp
      }
    }
    return a.isEmpty ? b.count : row[b.count]
  }
}
