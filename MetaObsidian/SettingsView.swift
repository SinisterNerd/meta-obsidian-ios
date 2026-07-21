import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.wakePhrase) private var wakePhrase = SettingsKeys.defaultWakePhrase
    @AppStorage(SettingsKeys.silenceTimeoutSeconds) private var silenceTimeoutSeconds = SettingsKeys.defaultSilenceTimeoutSeconds
    @AppStorage(SettingsKeys.vaultSubfolder) private var vaultSubfolder = SettingsKeys.defaultVaultSubfolder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Wake Phrase") {
                    TextField("Wake phrase", text: $wakePhrase)
                        .autocorrectionDisabled()
                    Text("Say this to start a conversation — e.g. \"Hey Aria\" if you've named your assistant. Takes effect next time you start listening.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Conversation") {
                    Stepper("Silence timeout: \(Int(silenceTimeoutSeconds))s", value: $silenceTimeoutSeconds, in: 3...30, step: 1)
                    Text("How long to wait after you stop talking before the conversation ends automatically.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Vault") {
                    TextField("Folder name", text: $vaultSubfolder)
                        .autocorrectionDisabled()
                    Text("Notes are saved as new files in this folder, created at the root of your chosen vault folder. Takes effect on the next save.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

enum SettingsKeys {
    static let wakePhrase = "wakePhrase"
    static let silenceTimeoutSeconds = "silenceTimeoutSeconds"
    static let vaultSubfolder = "vaultSubfolder"

    static let defaultWakePhrase = "hey obsidian"
    static let defaultSilenceTimeoutSeconds = 8.0
    static let defaultVaultSubfolder = "metaObsidian"
}

#Preview {
    SettingsView()
}
