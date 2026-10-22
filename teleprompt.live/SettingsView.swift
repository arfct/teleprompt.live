import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @AppStorage("smoothScroll") private var smoothScroll = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Voice Recognition", selection: engineBinding) {
            ForEach(TranscriptionEngineKind.allCases) { kind in
              Text(kind.displayName).tag(kind)
            }
          }
        } footer: {
          Text("On-device recognition is private and works offline. Deepgram sends audio to the cloud and needs an API key.")
        }

        Section {
          Toggle("Smooth Scroll", isOn: $smoothScroll)
        } footer: {
          Text("Keeps the script moving at your speaking pace, so upcoming lines are on screen as you reach them. When off, the current line jumps to the middle as you finish each one.")
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var engineBinding: Binding<TranscriptionEngineKind> {
    Binding(get: { appDelegate.selectedEngineKind },
            set: { appDelegate.selectedEngineKind = $0 })
  }
}
