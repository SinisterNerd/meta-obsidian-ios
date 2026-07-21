import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var wearables: WearablesManager
    @EnvironmentObject private var audioRecorder: AudioRecorder
    @EnvironmentObject private var wakeWordListener: WakeWordListener
    @EnvironmentObject private var realtimeClient: RealtimeVoiceClient
    @EnvironmentObject private var vaultManager: VaultManager
    @State private var showingSettings = false
    @State private var showingVaultPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Meta Obsidian")
                    .font(.title)

                Button("Settings") {
                    showingSettings = true
                }

                wakeWordSection
                Divider()
                wearablesSection
                Divider()
                recordingSection
                Divider()
                saveSection
                Divider()
                realtimeSection
            }
            .padding()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fileImporter(isPresented: $showingVaultPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                vaultManager.setVaultFolder(url)
            case .failure(let error):
                vaultManager.errorMessage = "Folder selection failed: \(error.localizedDescription)"
            }
        }
    }

    private var wakeWordSection: some View {
        Group {
            Button(wakeWordListener.isListening ? "Stop Listening for Wake Word" : "Start Listening for Wake Word") {
                Task {
                    if wakeWordListener.isListening {
                        wakeWordListener.stop()
                    } else {
                        await wakeWordListener.start()
                    }
                }
            }

            if wakeWordListener.isListening {
                Text("Listening for \"\(wakeWordListener.wakePhrase)\"…")
                    .font(.footnote)
                if !wakeWordListener.lastPartialTranscript.isEmpty {
                    Text(wakeWordListener.lastPartialTranscript)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let error = wakeWordListener.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
    }

    private var wearablesSection: some View {
        Group {
            Text("Registration: \(wearables.registrationState?.description ?? "nil")")
            Text("Devices: \(wearables.devices.count)")
            ForEach(wearables.devices, id: \.self) { id in
                Text("  \(id.prefix(8)): \(wearables.linkStates[id].map(String.init(describing:)) ?? "unknown"), \(wearables.compatibilities[id]?.displayString ?? "unknown")")
                    .font(.footnote)
            }
            Text("Camera permission: \(String(describing: wearables.cameraPermission))")
            Text("Session: \(String(describing: wearables.sessionState))")

            Button("Register with Meta AI app") {
                wearables.startRegistration()
            }
            Button("Request camera permission") {
                Task { await wearables.requestCameraPermission() }
            }
            Button("Connect") {
                Task { await wearables.connect() }
            }
            Button("Disconnect") {
                wearables.disconnect()
            }
            Button("Update Firmware") {
                wearables.updateFirmware()
            }
        }
    }

    private var recordingSection: some View {
        Group {
            Button(audioRecorder.isRecording ? "Stop Recording" : "Start Recording") {
                Task {
                    if audioRecorder.isRecording {
                        await audioRecorder.stopRecording()
                    } else {
                        await audioRecorder.startRecording()
                    }
                }
            }
            .disabled(audioRecorder.isTranscribing)

            if audioRecorder.isTranscribing {
                Text("Transcribing…")
            }

            if !audioRecorder.transcript.isEmpty {
                Text(audioRecorder.transcript)
                    .padding(.horizontal)
            }

            Button("Ask Assistant") {
                Task { await audioRecorder.askAssistant() }
            }
            .disabled(audioRecorder.transcript.isEmpty || audioRecorder.isAsking)

            if audioRecorder.isAsking {
                Text("Asking…")
            }

            if !audioRecorder.assistantReply.isEmpty {
                Text(audioRecorder.assistantReply)
                    .padding(.horizontal)
                    .foregroundColor(.blue)
            }

            if let error = audioRecorder.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
    }

    private var saveSection: some View {
        Group {
            Text("Vault: \(vaultManager.vaultURL?.lastPathComponent ?? "not selected")")

            Button("Choose Vault Folder") {
                showingVaultPicker = true
            }

            Button("Save Note") {
                var content = "**You:** \(audioRecorder.transcript)"
                if !audioRecorder.assistantReply.isEmpty {
                    content += "\n\n**Assistant:** \(audioRecorder.assistantReply)"
                }
                vaultManager.saveNote(content)
            }
            .disabled(audioRecorder.transcript.isEmpty || vaultManager.vaultURL == nil)

            if let filename = vaultManager.lastSavedFilename {
                Text("Saved: \(filename)")
                    .foregroundColor(.green)
                    .font(.footnote)
            }

            if let error = vaultManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
    }

    private var realtimeSection: some View {
        Group {
            Text("Realtime Voice").font(.headline)

            Button(realtimeClient.isActive ? "End Conversation" : "Start Voice Conversation") {
                Task {
                    if realtimeClient.isActive {
                        realtimeClient.stop()
                    } else {
                        await realtimeClient.start()
                    }
                }
            }

            if realtimeClient.isActive {
                Text(realtimeClient.isResponding ? "Assistant responding…" : "Listening…")
                    .font(.footnote)
            }

            if !realtimeClient.currentUserTurn.isEmpty {
                Text("You: \(realtimeClient.currentUserTurn)")
                    .padding(.horizontal)
            }

            if !realtimeClient.currentAssistantTurn.isEmpty {
                Text("Assistant: \(realtimeClient.currentAssistantTurn)")
                    .padding(.horizontal)
                    .foregroundColor(.blue)
            }

            if !realtimeClient.conversationTranscript.isEmpty {
                Text(realtimeClient.conversationTranscript)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            if let error = realtimeClient.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WearablesManager())
        .environmentObject(AudioRecorder())
        .environmentObject(WakeWordListener())
        .environmentObject(RealtimeVoiceClient())
        .environmentObject(VaultManager())
}
