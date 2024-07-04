import SwiftUI

struct ScriptScrollView: View {
  @State private var text: String
  
  init(withText: String) {
    self.text = withText
  }
  
  
  var paragraphs: [String] {
      text.components(separatedBy: "\n\n")
  }

  var body: some View {
      ScrollView {
          VStack(alignment: .leading, spacing: 20) {
              ForEach(paragraphs, id: \.self) { paragraph in
                  WordsView(words: paragraph.components(separatedBy: " "))
              }
          }
          .padding()
          .background(Color.black)
      }
      .background(Color.black)
  }
}

struct WordsView: View {
  let words: [String]

  var body: some View {
      VStack(alignment: .leading) {
          ForEach(layoutWords(in: UIScreen.main.bounds.width), id: \.self) { line in
              HStack(spacing: 5) {
                  ForEach(line, id: \.self) { word in
                      Text(word)
                      .font(.title)
                      .foregroundColor(Color.white)
                          .padding(5)
                          .background(Color.blue.opacity(0.3))
                          .cornerRadius(5)
                  }
              }.background(Color.black)
          }
      }.background(Color.black)
  }

  private func layoutWords(in width: CGFloat) -> [[String]] {
      var lines: [[String]] = []
      var currentLine: [String] = []
      var currentLineWidth: CGFloat = 0

      for word in words {
          let wordWidth = word.widthOfString(usingFont: .systemFont(ofSize: 32)) + 20 // 5 padding on each side
          if currentLineWidth + wordWidth > width {
              lines.append(currentLine)
              currentLine = [word]
              currentLineWidth = wordWidth
          } else {
              currentLine.append(word)
              currentLineWidth += wordWidth
          }
      }

      if !currentLine.isEmpty {
          lines.append(currentLine)
      }

      return lines
  }
}

extension String {
  func widthOfString(usingFont font: UIFont) -> CGFloat {
      let fontAttributes = [NSAttributedString.Key.font: font]
      let size = (self as NSString).size(withAttributes: fontAttributes)
      return size.width
  }
}

struct ScriptScrollView_Previews: PreviewProvider {
  static var previews: some View {
    let gettysburg = """
Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.

Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived and so dedicated, can long endure. We are met on a great battle-field of that war. We have come to dedicate a portion of that field, as a final resting place for those who here gave their lives that that nation might live. It is altogether fitting and proper that we should do this.

But, in a larger sense, we can not dedicate—we can not consecrate—we can not hallow—this ground. The brave men, living and dead, who struggled here, have consecrated it, far above our poor power to add or detract. The world will little note, nor long remember what we say here, but it can never forget what they did here. It is for us the living, rather, to be dedicated here to the unfinished work which they who fought here have thus far so nobly advanced. It is rather for us to be here dedicated to the great task remaining before us—that from these honored dead we take increased devotion to that cause for which they gave the last full measure of devotion—that we here highly resolve that these dead shall not have died in vain—that this nation, under God, shall have a new birth of freedom—and that government of the people, by the people, for the people, shall not perish from the earth.
"""
    ScriptScrollView(withText: gettysburg)
  }
}
