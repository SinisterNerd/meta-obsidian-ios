import SwiftUI
import MWDATCore

@main
struct MetaObsidianApp: App {
    @StateObject private var wearables = WearablesManager()
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var wakeWordListener = WakeWordListener()
    @StateObject private var realtimeClient = RealtimeVoiceClient()
    @StateObject private var vaultManager = VaultManager()

    init() {
        do {
            try Wearables.configure()
            print("Wearables.configure() succeeded")
        } catch {
            print("Wearables.configure() failed: \(error)")
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wearables)
                .environmentObject(audioRecorder)
                .environmentObject(wakeWordListener)
                .environmentObject(realtimeClient)
                .environmentObject(vaultManager)
                .onAppear {
                    wakeWordListener.onWakeWordDetected = {
                        print("Wake word detected")
                        Task { await realtimeClient.start() }
                    }
                    realtimeClient.onConversationEnded = { transcript in
                        print("Conversation ended:\n\(transcript)")
                        // Direct file write — no app-switch, no foreground
                        // requirement, so no ordering/race concerns with resuming
                        // wake-word listening right away (unlike the Obsidian-URI
                        // approach this replaced, which failed whenever this app
                        // wasn't already in the foreground — see project history).
                        if !transcript.isEmpty {
                            vaultManager.saveNote(transcript)
                        }
                        Task { await wakeWordListener.start() }
                    }
                }
                .onOpenURL { url in
                    print("onOpenURL received: \(url)")
                    Task {
                        do {
                            let handled = try await Wearables.shared.handleUrl(url)
                            print("handleUrl result: \(handled)")
                        } catch {
                            print("handleUrl failed: \(error)")
                        }
                    }
                }
        }
    }
}
