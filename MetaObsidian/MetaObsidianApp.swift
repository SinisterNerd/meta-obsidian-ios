import SwiftUI
import MWDATCore

@main
struct MetaObsidianApp: App {
    @StateObject private var wearables = WearablesManager()

    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wearables)
                .onOpenURL { url in
                    Task { try? await Wearables.shared.handleUrl(url) }
                }
        }
    }
}
