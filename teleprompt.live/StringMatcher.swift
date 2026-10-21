import Foundation

class StringMatcher {

  func preprocessText(_ text: String) -> String {
      let lowercased = text.lowercased()
      let cleaned = lowercased.replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
      return cleaned
  }
  
  func levenshtein(_ a: String, _ b: String) -> Int {
      let aCount = a.count
      let bCount = b.count
      
      if aCount == 0 { return bCount }
      if bCount == 0 { return aCount }
      
      var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)
      
      for i in 0...aCount {
          matrix[i][0] = i
      }
      
      for j in 0...bCount {
          matrix[0][j] = j
      }
      
      for i in 1...aCount {
          for j in 1...bCount {
              if a[a.index(a.startIndex, offsetBy: i - 1)] == b[b.index(b.startIndex, offsetBy: j - 1)] {
                  matrix[i][j] = matrix[i - 1][j - 1]
              } else {
                  matrix[i][j] = min(matrix[i - 1][j - 1] + 1, min(matrix[i][j - 1] + 1, matrix[i - 1][j] + 1))
              }
          }
      }
      
      return matrix[aCount][bCount]
  }

  func similarity(_ a: String, _ b: String) -> Double {
    return SequenceMatcher(a: a, b: b).ratio()
  }
  
  /// Scores each sentence against both the whole transcript and its last N
  /// words (N = the sentence's word count), keeping the better. Live engines
  /// report a growing in-progress phrase that can span several sentences;
  /// comparing the full phrase against one sentence would dilute the ratio
  /// and lag behind the speaker.
  func findBestMatch(transcription: String, sentences: [String]) -> (bestMatch: String?, bestIndex: Int, maxSimilarity: Double) {
      let preprocessedTranscription = preprocessText(transcription)
      let transcriptWords = preprocessedTranscription.split(separator: " ")
      var maxSimilarity = 0.0
      var bestMatch: String?
      var bestIndex = -1

      for (i, sentence) in sentences.enumerated() {
          let preprocessedSentence = preprocessText(sentence)
          let sentenceWordCount = preprocessedSentence.split(separator: " ").count
          var simScore = similarity(preprocessedTranscription, preprocessedSentence)
          if transcriptWords.count > sentenceWordCount, sentenceWordCount > 0 {
              let tail = transcriptWords.suffix(sentenceWordCount).joined(separator: " ")
              simScore = max(simScore, similarity(tail, preprocessedSentence))
          }
          if simScore > maxSimilarity {
              maxSimilarity = simScore
              bestMatch = sentence
              bestIndex = i
          }
      }

      return (bestMatch, bestIndex, maxSimilarity)
  }
  
}
