import SwiftUI
import MWDATCore

@main
struct MetaObsidianApp: App {
    @StateObject private var wearables = WearablesManager()
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var wakeWordListener = WakeWordListener()
    @StateObject private var realtimeClient = RealtimeVoiceClient()

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
                .onAppear {
                    wakeWordListener.onWakeWordDetected = {
                        print("Wake word detected")
                        Task { await realtimeClient.start() }
                    }
                    realtimeClient.onConversationEnded = { transcript in
                        print("Conversation ended:\n\(transcript)")
                        // Resume immediately rather than waiting on Obsidian's
                        // x-success callback — that's unreliable for the "daily"
                        // action (see project history), so relying on it alone left
                        // wake-word listening stuck off after every real save.
                        // start() no-ops if already listening, so this is harmless
                        // even if the onOpenURL branch below also fires.
                        //
                        // But: don't fire it at the exact same instant as the
                        // UIApplication.open() call below — reactivating our own
                        // audio session right as we ask iOS to hand off to another
                        // app caused the handoff itself to fail once (observed
                        // LSApplicationWorkspaceErrorDomain Code=115). Wait for
                        // open()'s completion handler first.
                        if !transcript.isEmpty, let url = ObsidianClient.dailyNoteAppendURL(content: transcript) {
                            UIApplication.shared.open(url) { success in
                                print("UIApplication.shared.open(obsidian) success=\(success)")
                                Task { await wakeWordListener.start() }
                            }
                        } else {
                            Task { await wakeWordListener.start() }
                        }
                    }
                }
                .onOpenURL { url in
                    print("onOpenURL received: \(url)")

                    if url.host == ObsidianClient.returnCallbackHost {
                        print("Returned from Obsidian after saving")
                        audioRecorder.savedToObsidian = true
                        Task { await wakeWordListener.start() }
                        return
                    }

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
