import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var wearables: WearablesManager
    @EnvironmentObject private var audioRecorder: AudioRecorder

    var body: some View {
        VStack(spacing: 16) {
            Text("Meta Obsidian")
                .font(.title)

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

            Divider()

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

            if let error = audioRecorder.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(WearablesManager())
        .environmentObject(AudioRecorder())
}
