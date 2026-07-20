import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var wearables: WearablesManager
    @EnvironmentObject private var audioRecorder: AudioRecorder
    @EnvironmentObject private var vaultManager: VaultManager
    @State private var showingVaultPicker = false

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

            Divider()

            Text("Vault: \(vaultManager.vaultURL?.lastPathComponent ?? "not selected")")

            Button("Choose Vault Folder") {
                showingVaultPicker = true
            }

            Button("Save to Obsidian") {
                vaultManager.saveTranscript(audioRecorder.transcript)
            }
            .disabled(audioRecorder.transcript.isEmpty || vaultManager.vaultURL == nil)

            if let filename = vaultManager.lastSavedFilename {
                Text("Saved: \(filename)")
                    .font(.footnote)
            }

            if let error = vaultManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
        .padding()
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

#Preview {
    ContentView()
        .environmentObject(WearablesManager())
        .environmentObject(AudioRecorder())
        .environmentObject(VaultManager())
}
