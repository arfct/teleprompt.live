import SwiftUI
import SwiftData

/// Root screen: a grid of script cards.
struct DocPickerView: View {
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @EnvironmentObject private var google: GoogleAccount
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL

  @Query(sort: \CachedDocument.createdTimestamp, order: .reverse)
  private var scripts: [CachedDocument]

  @State private var showNewScript = false
  @State private var showAddGoogleDoc = false
  @State private var showSettings = false
  @State private var editingScript: CachedDocument?
  @State private var path: [PersistentIdentifier] = []
  #if DEBUG
  @State private var demoDidRun = false
  #endif

  /// Shared by each card (zoom source) and its teleprompter (zoom destination).
  @Namespace private var zoom

  private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
          ForEach(scripts) { script in
            NavigationLink(value: script.persistentModelID) {
              ScriptCard(script: script, zoom: zoom)
            }
            .buttonStyle(.plain)
            .contextMenu { actions(for: script) }
          }
        }
        .padding(.horizontal)
        .padding(.bottom)
      }
      .navigationDestination(for: PersistentIdentifier.self) { id in
        if let script = scripts.first(where: { $0.persistentModelID == id }) {
          destination(for: script)
            .navigationTransition(.zoom(sourceID: id, in: zoom))
        }
      }
      #if DEBUG
      .task {
        // `-UIDemoZoom`: open the first card, then go back, for recording
        // the zoom transition in the simulator.
        guard !demoDidRun, let first = scripts.first else { return }
        let args = ProcessInfo.processInfo.arguments
        // `-UIDemoOpen`: open the first card and stay (teleprompter demos).
        if args.contains("-UIDemoOpen") {
          demoDidRun = true
          path = [first.persistentModelID]
          return
        }
        if args.contains("-UIDemoSettings") {
          demoDidRun = true
          showSettings = true
          return
        }
        guard args.contains("-UIDemoZoom") else { return }
        demoDidRun = true
        // Slow Core Animation so simulator recordings (which drop frames
        // during fast animations) capture the whole transition.
        GoogleAccount.topViewController()?.view.window?.layer.speed = 0.2
        try? await Task.sleep(for: .seconds(2))
        path = [first.persistentModelID]
        try? await Task.sleep(for: .seconds(5))
        path = []
      }
      #endif
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
        // One group, so the system draws a single control holding both menus.
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
      .sheet(isPresented: $showSettings) {
        SettingsView()
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
      Button {
        showSettings = true
      } label: {
        Label("Settings…", systemImage: "gearshape")
      }

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
      Label("More", systemImage: "ellipsis")
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
      TelepromptView(source: .googleDoc(id: script.googleDocId, authState: authState), cache: script)
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

/// A square preview of the script, styled like the teleprompter it opens
/// into (white on black), with the title and date underneath.
private struct ScriptCard: View {
  let script: CachedDocument
  let zoom: Namespace.ID

  private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      preview
        .aspectRatio(1, contentMode: .fit)
        .matchedTransitionSource(id: script.persistentModelID, in: zoom)

      VStack(alignment: .leading, spacing: 1) {
        Text(script.title ?? "Untitled")
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .padding(.horizontal, 4)
    }
    .contentShape(Rectangle())
  }

  private var preview: some View {
    Self.shape
      .fill(Color.black)
      .overlay {
        if let text = previewText {
          // A card-sized clear view anchors the (taller) text to the top
          // and gives the fade mask the card's bounds, so long scripts
          // run off the bottom and fade instead of centering or truncating.
          Color.clear
            .overlay(alignment: .topLeading) {
              Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
            }
            .mask {
              LinearGradient(stops: [.init(color: .black, location: 0.7),
                                     .init(color: .clear, location: 0.97)],
                             startPoint: .top, endPoint: .bottom)
            }
        } else {
          Image(systemName: "doc.text")
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.white.opacity(0.45))
        }
      }
      .clipShape(Self.shape)
      .overlay {
        Self.shape.strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
      }
  }

  private var previewText: String? {
    guard let body = script.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
    return String(body.prefix(400))
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
