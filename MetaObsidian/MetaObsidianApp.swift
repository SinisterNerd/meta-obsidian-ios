import SwiftUI
import MWDATCore

@main
struct MetaObsidianApp: App {
    @StateObject private var wearables = WearablesManager()
    @StateObject private var audioRecorder = AudioRecorder()
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
                .environmentObject(vaultManager)
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
