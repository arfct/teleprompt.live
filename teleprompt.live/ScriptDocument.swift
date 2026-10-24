import Foundation
import NaturalLanguage

/// A script broken into paragraphs → sentences → words, with each word's
/// character range so the view can color words inside a sentence's text.
struct ScriptDocument {
  struct Word {
    /// Lowercased, apostrophes removed: what transcripts are compared to.
    let normalized: String
    /// Range within the owning sentence's `text`.
    let range: Range<String.Index>
    let sentence: Int
    /// Unstressed in speech (article, preposition, pronoun, helper verb…).
    var isFunctionWord = false
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
        let functionWordStarts = Self.functionWordStarts(in: sentenceText)
        for match in sentenceText.matches(of: Self.wordPattern) {
          let normalized = Self.normalize(String(sentenceText[match.range]))
          words.append(Word(normalized: normalized,
                            range: match.range,
                            sentence: sentences.count,
                            isFunctionWord: functionWordStarts.contains(match.range.lowerBound)
                              && !Self.alwaysStressed.contains(normalized)
                              && !normalized.hasSuffix("nt")))
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

  // MARK: - Function words

  /// Closed-class parts of speech that are unstressed when spoken.
  private static let functionClasses: Set<NLTag> = [.determiner, .preposition, .conjunction, .pronoun, .particle, .classifier]
  /// Forms of "be" and modals: unstressed whenever they're verbs.
  private static let alwaysLightVerbs: Set<String> = [
    "be", "am", "is", "are", "was", "were", "been", "being",
    "will", "would", "shall", "should", "can", "could", "may", "might", "must",
  ]
  /// "have"/"do" are helpers only before another verb, adverb or "not"
  /// ("had not intended", "have often longed"); as main verbs ("have a
  /// few things", "than you do") they're stressed.
  private static let helperVerbs: Set<String> = ["have", "has", "had", "having", "do", "does", "did"]
  /// Carry meaning even though they're short.
  static let alwaysStressed: Set<String> = ["not", "no", "never", "nor", "none", "nothing", "neither"]

  /// Start indices of function words in `text`. Negative contractions
  /// ("don't") are excluded by the caller via their "nt" ending. Uses
  /// NaturalLanguage's lexical classes; if the tagger has no model on this
  /// device (it returns no classes), falls back to a closed-class word list.
  static func functionWordStarts(in text: String) -> Set<String.Index> {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text
    var tokens: [(range: Range<String.Index>, tag: NLTag?, word: String)] = []
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                         options: [.omitWhitespace, .omitPunctuation]) { tag, range in
      tokens.append((range, tag, normalize(String(text[range]))))
      return true
    }
    let tagged = tokens.contains { $0.tag != nil && $0.tag != .otherWord }
    var starts = Set<String.Index>()
    for (i, token) in tokens.enumerated() {
      let next = i + 1 < tokens.count ? tokens[i + 1] : nil
      let light: Bool
      if tagged {
        guard let tag = token.tag else { continue }
        if tag == .verb && alwaysLightVerbs.contains(token.word) {
          light = true
        } else if tag == .verb && helperVerbs.contains(token.word) {
          light = next.map { $0.tag == .verb || $0.tag == .adverb || alwaysStressed.contains($0.word) || $0.word == "nt" } ?? false
        } else {
          light = functionClasses.contains(tag)
        }
      } else {
        if helperVerbs.contains(token.word) {
          // Without tags: a helper only before "not"/"n't" or a past participle.
          light = next.map { alwaysStressed.contains($0.word) || $0.word == "nt" || $0.word.hasSuffix("ed") || $0.word.hasSuffix("en") } ?? false
        } else {
          light = alwaysLightVerbs.contains(token.word) || closedClassWords.contains(token.word)
        }
      }
      if light { starts.insert(token.range.lowerBound) }
    }
    return starts
  }

  /// Articles, determiners, pronouns, prepositions and conjunctions:
  /// closed classes, so a list covers them when no tagger model exists.
  /// Ambiguous words that are often stressed (like, up, out, one, some
  /// uses of "that") are left out.
  private static let closedClassWords: Set<String> = [
    // articles & determiners
    "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
    "whose", "what", "which", "each", "every", "either", "any", "some", "such",
    // pronouns
    "i", "me", "you", "he", "him", "she", "it", "we", "us", "they", "them", "who", "whom",
    "myself", "yourself", "himself", "herself", "itself", "ourselves", "yourselves", "themselves",
    // prepositions
    "of", "in", "on", "at", "to", "for", "with", "by", "from", "about", "into", "onto", "upon", "over",
    "under", "through", "between", "among", "against", "during", "without", "within", "across",
    "toward", "towards", "as", "than",
    // conjunctions
    "and", "or", "but", "so", "yet", "if", "because", "although", "though", "while", "whereas",
    "whether", "unless", "until", "since", "when", "where",
  ]

  /// Downloads the tagger's English model if this device lacks it, so
  /// later documents get proper part-of-speech tags.
  static func prepareTagger() {
    NLTagger.requestAssets(for: .english, tagScheme: .lexicalClass) { _, _ in }
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
