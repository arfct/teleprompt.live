import SwiftUI
import SwiftData
import Starscream

@main
struct teleprompt_liveApp: App {
  @UIApplicationDelegateAdaptor private var appDelegate : TelepromptAppDelegate
  
  @AppStorage("selectedTab") var selectedTab = "scripts"

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      CachedDocument.self,
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    
    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()
  
  var body: some Scene {
    WindowGroup {
      //TelepromptTabView(selectedTab: $selectedTab)
      DocPickerView()
    }
    .modelContainer(sharedModelContainer)
  }
}
