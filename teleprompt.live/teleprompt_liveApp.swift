import SwiftUI
import SwiftData

@main
struct teleprompt_liveApp: App {
  @UIApplicationDelegateAdaptor private var appDelegate: TelepromptAppDelegate
  @StateObject private var google = GoogleAccount()

  init() {
    ScriptDocument.prepareTagger()
  }

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      CachedDocument.self,
    ])
    #if DEBUG
    // `-UISampleScripts` launches with an in-memory store of sample scripts,
    // for screenshots and UI checks.
    let inMemory = ProcessInfo.processInfo.arguments.contains("-UISampleScripts")
    #else
    let inMemory = false
    #endif
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

    do {
      let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
      #if DEBUG
      if inMemory { SampleScripts.insert(into: container) }
      #endif
      if !inMemory { StarterScripts.seedIfNeeded(into: container) }
      return container
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      DocPickerView()
        .environmentObject(google)
    }
    .modelContainer(sharedModelContainer)
  }
}

#if DEBUG
enum SampleScripts {
  static func insert(into container: ModelContainer) {
    let context = ModelContext(container)
    let day: TimeInterval = 86_400
    let now = Date()
    context.insert(CachedDocument(createdTimestamp: now.addingTimeInterval(-6 * day), googleDocId: "sample-doc-1",
                                  lastFetchedTimestamp: now.addingTimeInterval(-6 * day),
                                  title: "Q4 All-Hands Opening",
                                  body: "Good morning, everyone. Thanks for being here. It's been a big quarter, and I want to start with the people who made it happen."))
    context.insert(CachedDocument(createdTimestamp: now.addingTimeInterval(-3 * day), googleDocId: "",
                                  lastFetchedTimestamp: now.addingTimeInterval(-3 * day),
                                  title: "Product Launch Keynote",
                                  body: String(repeating: "Today we're introducing something new. ", count: 60)))
    context.insert(CachedDocument(createdTimestamp: now.addingTimeInterval(-1 * day), googleDocId: "sample-doc-2",
                                  title: "Wedding Toast"))
    context.insert(CachedDocument(createdTimestamp: now.addingTimeInterval(-2 * 3600), googleDocId: "",
                                  lastFetchedTimestamp: now.addingTimeInterval(-2 * 3600),
                                  title: "Conference Talk",
                                  body: "Hi, I'm Nick. For the next twenty minutes I want to talk about the gap between what we say and what we read."))
    context.insert(CachedDocument(createdTimestamp: now, googleDocId: "",
                                  lastFetchedTimestamp: now,
                                  title: "Podcast Intro",
                                  body: "Welcome back to the show. This week we talk about how teleprompters actually work."))
    // Starter script last, so it's newest and leads the grid.
    StarterScripts.insertAll(into: context)
    try? context.save()
  }
}
#endif
