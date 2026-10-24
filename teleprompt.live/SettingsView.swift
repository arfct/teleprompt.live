import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appDelegate: TelepromptAppDelegate
  @AppStorage("smoothScroll") private var smoothScroll = true
  @AppStorage("lightFunctionWords") private var lightFunctionWords = true
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        if TranscriptionEngineKind.available.count > 1 {
          Section {
            Picker("Voice Recognition", selection: engineBinding) {
              ForEach(TranscriptionEngineKind.available) { kind in
                Text(kind.displayName).tag(kind)
              }
            }
          } footer: {
            Text("On-device recognition is private and works offline. Deepgram sends audio to the cloud and needs an API key.")
          }
        }

        Section {
          Toggle("Smooth Scroll", isOn: $smoothScroll)
        } footer: {
          Text("Scrolls steadily at your average speaking pace and coasts to a stop when you pause. When off, the current line jumps to the middle as you finish each one.")
        }

        Section {
          Toggle("Lighter Small Words", isOn: $lightFunctionWords)
        } footer: {
          Text("Sets words you don't stress when speaking (the, of, and, it, would) in a lighter weight, so the important words stand out.")
        }

        Section {
          Link("Support", destination: URL(string: "https://teleprompt.fyi/support/")!)
          Link("Privacy Policy", destination: URL(string: "https://teleprompt.fyi/privacy/")!)
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
