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
                    realtimeClient.onConversationEnded = { userText, assistantText in
                        print("Conversation ended: user=\(userText) assistant=\(assistantText)")
                        guard !userText.isEmpty || !assistantText.isEmpty else {
                            Task { await wakeWordListener.start() }
                            return
                        }
                        var content = "**You:** \(userText)"
                        if !assistantText.isEmpty {
                            content += "\n\n**Assistant:** \(assistantText)"
                        }
                        if let url = ObsidianClient.dailyNoteAppendURL(content: content) {
                            UIApplication.shared.open(url)
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
