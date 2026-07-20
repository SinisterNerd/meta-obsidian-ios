import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var wearables: WearablesManager
    @EnvironmentObject private var audioRecorder: AudioRecorder
    @EnvironmentObject private var wakeWordListener: WakeWordListener
    @EnvironmentObject private var realtimeClient: RealtimeVoiceClient
    @Environment(\.openURL) private var openURL
    @State private var obsidianError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Meta Obsidian")
                    .font(.title)

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
            Button("Save to Daily Note") {
                var content = "**You:** \(audioRecorder.transcript)"
                if !audioRecorder.assistantReply.isEmpty {
                    content += "\n\n**Assistant:** \(audioRecorder.assistantReply)"
                }
                guard let url = ObsidianClient.dailyNoteAppendURL(content: content) else {
                    obsidianError = "Couldn't build Obsidian URI"
                    return
                }
                audioRecorder.savedToObsidian = false
                openURL(url) { accepted in
                    if !accepted {
                        obsidianError = "Obsidian didn't open — is it installed?"
                    }
                }
            }
            .disabled(audioRecorder.transcript.isEmpty)

            if audioRecorder.savedToObsidian {
                Text("Saved ✓")
                    .foregroundColor(.green)
                    .font(.footnote)
            }

            if let obsidianError {
                Text(obsidianError)
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
}
