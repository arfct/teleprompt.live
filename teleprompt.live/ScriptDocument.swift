import Foundation

/// A script broken into paragraphs → sentences → words, with each word's
/// character range so the view can color words inside a sentence's text.
struct ScriptDocument {
  struct Word {
    /// Lowercased, apostrophes removed: what transcripts are compared to.
    let normalized: String
    /// Range within the owning sentence's `text`.
    let range: Range<String.Index>
    let sentence: Int
  }

  struct Sentence {
    let text: String
    let paragraph: Int
    /// Indices into `words`.
    let wordRange: Range<Int>
  }

  private(set) var words: [Word] = []
  private(set) var sentences: [Sentence] = []
  /// Sentence index ranges, one per paragraph.
  private(set) var paragraphs: [Range<Int>] = []

  static let empty = ScriptDocument(text: "")

  init(text: String) {
    let lines = text.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    for line in lines {
      let firstSentence = sentences.count
      for sentenceText in Self.splitSentences(line) {
        let firstWord = words.count
        for match in sentenceText.matches(of: Self.wordPattern) {
          words.append(Word(normalized: Self.normalize(String(sentenceText[match.range])),
                            range: match.range,
                            sentence: sentences.count))
        }
        sentences.append(Sentence(text: sentenceText, paragraph: paragraphs.count,
                                  wordRange: firstWord..<words.count))
      }
      if sentences.count > firstSentence {
        paragraphs.append(firstSentence..<sentences.count)
      }
    }
  }

  /// Letters/digits, allowing inner apostrophes ("don't", "one's").
  nonisolated(unsafe) static let wordPattern = #/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/#

  static func normalize(_ word: String) -> String {
    word.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  /// Normalized words of free text (e.g. a transcript).
  static func normalizedWords(in text: String) -> [String] {
    text.matches(of: wordPattern).map { normalize(String(text[$0.range])) }
  }

  /// Splits after . ! ? … (and any closing quotes/brackets) + whitespace.
  static func splitSentences(_ paragraph: String) -> [String] {
    var result: [String] = []
    var start = paragraph.startIndex
    for match in paragraph.matches(of: #/[.!?…]+["'”’)\]]*\s+/#) {
      let trimmed = paragraph[start..<match.range.upperBound].trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { result.append(trimmed) }
      start = match.range.upperBound
    }
    let tail = paragraph[start...].trimmingCharacters(in: .whitespaces)
    if !tail.isEmpty { result.append(tail) }
    return result
  }
}
