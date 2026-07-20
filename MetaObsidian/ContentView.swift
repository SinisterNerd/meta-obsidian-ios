import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var wearables: WearablesManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Meta Obsidian")
                .font(.title)

            Text("Registration: \(wearables.registrationState?.description ?? "nil")")
            Text("Devices: \(wearables.devices.count)")
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
        }
        .padding()
    }
}

#Preview {
    ContentView().environmentObject(WearablesManager())
}
