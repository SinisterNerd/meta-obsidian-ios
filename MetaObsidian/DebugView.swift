import SwiftUI

// Raw diagnostic controls used while building/debugging the Wearables SDK
// integration and the manual Whisper/Assistant pipeline. Not part of the normal
// day-to-day flow (wake word -> conversation -> save), kept for troubleshooting.
struct DebugView: View {
    @EnvironmentObject private var wearables: WearablesManager
    @EnvironmentObject private var audioRecorder: AudioRecorder
    @EnvironmentObject private var realtimeClient: RealtimeVoiceClient

    var body: some View {
        Form {
            Section("Wearables SDK") {
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

            Section("Manual Whisper + Assistant") {
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
                        .foregroundColor(.blue)
                }
                if let error = audioRecorder.errorMessage {
                    Text(error).foregroundColor(.red).font(.footnote)
                }
            }

            Section("Realtime Voice (raw)") {
                Text(realtimeClient.isActive ? (realtimeClient.isResponding ? "Responding…" : "Listening…") : "Inactive")
                    .font(.footnote)
                if !realtimeClient.conversationTranscript.isEmpty {
                    Text(realtimeClient.conversationTranscript)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if let error = realtimeClient.errorMessage {
                    Text(error).foregroundColor(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Debug")
    }
}

#Preview {
    NavigationView {
        DebugView()
            .environmentObject(WearablesManager())
            .environmentObject(AudioRecorder())
            .environmentObject(RealtimeVoiceClient())
    }
}
