import SwiftUI
import SwiftData

/// Root screen: the list of scripts.
struct DocPickerView: View {
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @EnvironmentObject private var google: GoogleAccount
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL

  @Query(sort: \CachedDocument.createdTimestamp, order: .reverse)
  private var scripts: [CachedDocument]

  @State private var showNewScript = false
  @State private var showAddGoogleDoc = false
  @State private var editingScript: CachedDocument?

  var body: some View {
    NavigationStack {
      List {
        ForEach(scripts) { script in
          NavigationLink {
            destination(for: script)
          } label: {
            ScriptRow(script: script)
          }
          .contextMenu { actions(for: script) }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              delete(script)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
      .overlay {
        if scripts.isEmpty {
          ContentUnavailableView {
            Label("No Scripts", systemImage: "captions.bubble")
          } description: {
            Text("Paste in a script, or add one from Google Docs.")
          } actions: {
            Button("New Script") { showNewScript = true }
              .buttonStyle(.borderedProminent)
            Button("Add Google Doc") { showAddGoogleDoc = true }
          }
        }
      }
      .navigationTitle("Scripts")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          moreMenu
          addMenu
        }
      }
      .sheet(isPresented: $showNewScript) {
        ScriptEditorView()
      }
      .sheet(item: $editingScript) { script in
        ScriptEditorView(document: script)
      }
      .sheet(isPresented: $showAddGoogleDoc) {
        AddGoogleDocView(existingIDs: Set(scripts.map(\.googleDocId)))
      }
      .alert("Couldn't Sign In", isPresented: signInErrorBinding) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(google.signInError ?? "")
      }
      .onOpenURL { url in
        if let flow = appDelegate.currentAuthorizationFlow, flow.resumeExternalUserAgentFlow(with: url) {
          appDelegate.currentAuthorizationFlow = nil
        }
      }
    }
  }

  // MARK: - Menus

  private var addMenu: some View {
    Menu {
      Button {
        showNewScript = true
      } label: {
        Label("New Script", systemImage: "square.and.pencil")
      }
      Button {
        showAddGoogleDoc = true
      } label: {
        Label("Add Google Doc", systemImage: "doc.badge.plus")
      }
    } label: {
      Label("Add", systemImage: "plus")
    }
  }

  private var moreMenu: some View {
    Menu {
      Picker(selection: engineBinding) {
        ForEach(TranscriptionEngineKind.allCases) { kind in
          Text(kind.displayName).tag(kind)
        }
      } label: {
        Label("Speech Recognition", systemImage: "waveform")
      }
      .pickerStyle(.menu)

      Section(google.email ?? "Google Account") {
        if google.isSignedIn {
          Button(role: .destructive) {
            google.signOut()
          } label: {
            Label("Sign Out of Google", systemImage: "rectangle.portrait.and.arrow.right")
          }
        } else {
          Button {
            google.signIn(appDelegate: appDelegate)
          } label: {
            Label("Sign In to Google", systemImage: "person.crop.circle")
          }
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis.circle")
    }
  }

  @ViewBuilder
  private func actions(for script: CachedDocument) -> some View {
    if script.isPastedText {
      Button {
        editingScript = script
      } label: {
        Label("Edit", systemImage: "pencil")
      }
    } else {
      Button {
        if let url = URL(string: "https://docs.google.com/document/d/\(script.googleDocId)/edit") {
          openURL(url)
        }
      } label: {
        Label("Open in Google Docs", systemImage: "arrow.up.forward.app")
      }
    }
    Divider()
    Button(role: .destructive) {
      delete(script)
    } label: {
      Label("Delete", systemImage: "trash")
    }
  }

  // MARK: - Destinations

  @ViewBuilder
  private func destination(for script: CachedDocument) -> some View {
    if script.isPastedText {
      TelepromptView(source: .text(title: script.title ?? "Script", body: script.body ?? ""))
    } else if let authState = google.authState {
      TelepromptView(source: .googleDoc(id: script.googleDocId, authState: authState))
    } else {
      ContentUnavailableView {
        Label("Sign In to Google", systemImage: "person.crop.circle")
      } description: {
        Text("This script is a Google Doc. Sign in to load it.")
      } actions: {
        Button("Sign In") { google.signIn(appDelegate: appDelegate) }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  // MARK: - Helpers

  private var engineBinding: Binding<TranscriptionEngineKind> {
    Binding(get: { appDelegate.selectedEngineKind },
            set: { appDelegate.selectedEngineKind = $0 })
  }

  private var signInErrorBinding: Binding<Bool> {
    Binding(get: { google.signInError != nil },
            set: { if !$0 { google.signInError = nil } })
  }

  private func delete(_ script: CachedDocument) {
    withAnimation {
      modelContext.delete(script)
    }
  }
}

/// One row in the script list: title plus a quiet secondary line.
private struct ScriptRow: View {
  let script: CachedDocument

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(script.title ?? "Untitled")
        .lineLimit(1)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private var subtitle: String {
    let when = script.lastFetchedTimestamp ?? script.createdTimestamp
    let date = Calendar.current.isDate(when, equalTo: .now, toGranularity: .year)
      ? when.formatted(.dateTime.month(.abbreviated).day())
      : when.formatted(date: .abbreviated, time: .omitted)
    if script.isPastedText {
      let words = (script.body ?? "").split(whereSeparator: { $0.isWhitespace }).count
      return "\(date) · \(words) words"
    }
    return "\(date) · Google Doc"
  }
}
