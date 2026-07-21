import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var vaultManager: VaultManager
    @AppStorage(SettingsKeys.wakePhrase) private var wakePhrase = SettingsKeys.defaultWakePhrase
    @AppStorage(SettingsKeys.silenceTimeoutSeconds) private var silenceTimeoutSeconds = SettingsKeys.defaultSilenceTimeoutSeconds
    @AppStorage(SettingsKeys.vaultSubfolder) private var vaultSubfolder = SettingsKeys.defaultVaultSubfolder
    @Environment(\.dismiss) private var dismiss
    @State private var showingVaultPicker = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.obsidianPurple)
                        Text(vaultManager.vaultURL?.lastPathComponent ?? "Not selected")
                        Spacer()
                        Button("Choose…") {
                            showingVaultPicker = true
                        }
                    }
                    TextField("Notes subfolder", text: $vaultSubfolder)
                        .autocorrectionDisabled()
                    if let error = vaultManager.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Each conversation is saved as a new note in this subfolder, created at the root of your chosen vault folder.")
                }

                Section {
                    TextField("Wake phrase", text: $wakePhrase)
                        .autocorrectionDisabled()
                } header: {
                    Text("Wake Phrase")
                } footer: {
                    Text("Say this to start a conversation — e.g. \"Hey Aria\" if you've named your assistant. Takes effect next time you start listening.")
                }

                Section {
                    Stepper("Silence timeout: \(Int(silenceTimeoutSeconds))s", value: $silenceTimeoutSeconds, in: 3...30, step: 1)
                } header: {
                    Text("Conversation")
                } footer: {
                    Text("How long to wait after you stop talking before the conversation ends automatically.")
                }

                Section {
                    NavigationLink("Debug Info") {
                        DebugView()
                    }
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
        .fileImporter(isPresented: $showingVaultPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                vaultManager.setVaultFolder(url)
            case .failure(let error):
                vaultManager.errorMessage = "Folder selection failed: \(error.localizedDescription)"
            }
        }
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
        .environmentObject(VaultManager())
}
