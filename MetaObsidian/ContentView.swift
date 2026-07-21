import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var wakeWordListener: WakeWordListener
    @EnvironmentObject private var realtimeClient: RealtimeVoiceClient
    @EnvironmentObject private var vaultManager: VaultManager
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard

                    if realtimeClient.isActive {
                        conversationCard
                    }

                    controls

                    if let filename = vaultManager.lastSavedFilename {
                        savedCard(filename)
                    }

                    if let error = currentError {
                        errorCard(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Meta Obsidian")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(.obsidianPurple)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var currentError: String? {
        wakeWordListener.errorMessage ?? realtimeClient.errorMessage ?? vaultManager.errorMessage
    }

    // MARK: - Status

    private var statusIcon: String {
        if realtimeClient.isActive { return "waveform" }
        if wakeWordListener.isListening { return "ear.fill" }
        return "moon.zzz.fill"
    }

    private var statusColor: Color {
        if realtimeClient.isActive { return .obsidianPurple }
        if wakeWordListener.isListening { return .green }
        return .secondary
    }

    private var statusText: String {
        if realtimeClient.isActive {
            return realtimeClient.isResponding ? "Responding…" : "Listening to you…"
        }
        if wakeWordListener.isListening {
            return "Listening for \"\(wakeWordListener.wakePhrase)\""
        }
        return "Idle"
    }

    private var statusCard: some View {
        VStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 44))
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(statusColor.opacity(0.12))
        .cornerRadius(20)
    }

    // MARK: - Active conversation

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !realtimeClient.currentUserTurn.isEmpty {
                Label(realtimeClient.currentUserTurn, systemImage: "person.fill")
            }
            if !realtimeClient.currentAssistantTurn.isEmpty {
                Label(realtimeClient.currentAssistantTurn, systemImage: "sparkles")
                    .foregroundColor(.obsidianPurple)
            }
            if realtimeClient.currentUserTurn.isEmpty && realtimeClient.currentAssistantTurn.isEmpty {
                Text("…")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if wakeWordListener.isListening {
                        wakeWordListener.stop()
                    } else {
                        await wakeWordListener.start()
                    }
                }
            } label: {
                Label(
                    wakeWordListener.isListening ? "Stop Listening" : "Start Listening",
                    systemImage: wakeWordListener.isListening ? "ear.trianglebadge.exclamationmark" : "ear.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(realtimeClient.isActive)

            Button {
                Task {
                    if realtimeClient.isActive {
                        realtimeClient.stop()
                    } else {
                        // Both use the mic — make sure wake-word listening isn't
                        // also holding it before starting a manual conversation.
                        if wakeWordListener.isListening {
                            wakeWordListener.stop()
                        }
                        await realtimeClient.start()
                    }
                }
            } label: {
                Label(
                    realtimeClient.isActive ? "End Conversation" : "Talk Now",
                    systemImage: realtimeClient.isActive ? "stop.circle.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Feedback

    private func savedCard(_ filename: String) -> some View {
        Label("Saved: \(filename)", systemImage: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundColor(.red)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
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
