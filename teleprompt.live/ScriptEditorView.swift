import SwiftUI
import SwiftData

/// Create or edit a script whose text lives in the app (pasted or typed),
/// rather than in a Google Doc.
struct ScriptEditorView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  /// nil = creating a new script.
  let document: CachedDocument?

  @State private var title: String
  @State private var text: String

  init(document: CachedDocument? = nil) {
    self.document = document
    _title = State(initialValue: document?.title ?? "")
    _text = State(initialValue: document?.body ?? "")
  }

  private var canSave: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var wordCount: Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Title", text: $title)
        }
        Section {
          TextEditor(text: $text)
            .frame(minHeight: 280)
        } header: {
          Text("Script")
        } footer: {
          HStack {
            if text.isEmpty {
              PasteButton(payloadType: String.self) { strings in
                guard let pasted = strings.first else { return }
                DispatchQueue.main.async { text = pasted }
              }
              .labelStyle(.titleAndIcon)
              .buttonBorderShape(.capsule)
            }
            Spacer()
            Text("\(wordCount) words")
          }
        }
      }
      .navigationTitle(document == nil ? "New Script" : "Edit Script")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(!canSave)
        }
      }
    }
  }

  private func save() {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmedTitle.isEmpty ? Self.defaultTitle(for: text) : trimmedTitle

    if let document {
      document.title = resolvedTitle
      document.body = text
      document.lastFetchedTimestamp = Date()
    } else {
      modelContext.insert(CachedDocument(createdTimestamp: Date(),
                                         googleDocId: "",
                                         lastFetchedTimestamp: Date(),
                                         title: resolvedTitle,
                                         body: text))
    }
    dismiss()
  }

  /// First line of the script, trimmed to a reasonable length.
  static func defaultTitle(for text: String) -> String {
    let firstLine = text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first(where: { !$0.isEmpty }) ?? "Untitled Script"
    return firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
  }
}
