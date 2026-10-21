import SwiftUI
import SwiftData
import GoogleAPIClientForREST_Drive

/// Sheet for picking a Google Doc to add as a script.
struct AddGoogleDocView: View {
  @EnvironmentObject private var google: GoogleAccount
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  /// Doc IDs already in the script list, shown as added.
  let existingIDs: Set<String>

  @State private var query = ""
  @State private var results: [GTLRDrive_File] = []
  @State private var isLoading = false
  @State private var loadError: String?

  var body: some View {
    NavigationStack {
      Group {
        if google.isSignedIn {
          docList
        } else {
          ContentUnavailableView {
            Label("Sign In to Google", systemImage: "person.crop.circle")
          } description: {
            Text("Sign in to choose a script from your Google Docs.")
          } actions: {
            Button("Sign In") { google.signIn(appDelegate: appDelegate) }
              .buttonStyle(.borderedProminent)
          }
        }
      }
      .navigationTitle("Add Google Doc")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private var docList: some View {
    List(results, id: \.identifier) { file in
      let alreadyAdded = existingIDs.contains(file.identifier ?? "")
      Button {
        add(file)
      } label: {
        HStack {
          Label(file.name ?? "Untitled", systemImage: "doc.text")
            .foregroundStyle(alreadyAdded ? .secondary : .primary)
          Spacer()
          if alreadyAdded {
            Image(systemName: "checkmark")
              .foregroundStyle(.secondary)
          }
        }
      }
      .disabled(alreadyAdded)
    }
    .overlay {
      if let loadError {
        ContentUnavailableView("Couldn't Load Docs", systemImage: "exclamationmark.triangle", description: Text(loadError))
      } else if isLoading && results.isEmpty {
        ProgressView()
      } else if results.isEmpty && !isLoading {
        if query.isEmpty {
          ContentUnavailableView("No Google Docs", systemImage: "doc.text")
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    .searchable(text: $query, prompt: "Search Google Docs")
    .task(id: query) {
      // Debounce typing.
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      await search()
    }
  }

  private func search() async {
    isLoading = true
    defer { isLoading = false }
    do {
      results = try await google.searchDocs(query)
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
  }

  private func add(_ file: GTLRDrive_File) {
    guard let id = file.identifier else { return }
    modelContext.insert(CachedDocument(createdTimestamp: Date(), googleDocId: id, title: file.name ?? "Untitled Doc"))
    dismiss()
  }
}
