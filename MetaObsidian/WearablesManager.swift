import Foundation
import MWDATCore
import MWDATCamera

@MainActor
final class WearablesManager: ObservableObject {
    @Published var registrationState: RegistrationState?
    @Published var devices: [DeviceIdentifier] = []
    @Published var cameraPermission: PermissionStatus = .denied
    @Published var sessionState: DeviceSessionState?

    private var session: DeviceSession?

    init() {
        registrationState = Wearables.shared.registrationState
        devices = Wearables.shared.devices
        Task { await observeRegistrationState() }
        Task { await observeDevices() }
        Task {
            cameraPermission = (try? await Wearables.shared.checkPermissionStatus(.camera)) ?? .denied
        }
    }

    func startRegistration() {
        Task {
            do {
                try await Wearables.shared.startRegistration()
            } catch {
                print("startRegistration failed: \(error)")
            }
        }
    }

    func requestCameraPermission() async {
        do {
            cameraPermission = try await Wearables.shared.requestPermission(.camera)
        } catch {
            print("requestPermission(.camera) failed: \(error)")
        }
    }

    func connect() async {
        do {
            let selector = AutoDeviceSelector(wearables: Wearables.shared)
            let session = try Wearables.shared.createSession(deviceSelector: selector)
            self.session = session
            try session.start()
            for await state in session.stateStream() {
                sessionState = state
            }
        } catch {
            print("connect failed: \(error)")
        }
    }

    func disconnect() {
        session?.stop()
        session = nil
    }

    private func observeRegistrationState() async {
        print("observeRegistrationState: starting to listen")
        for await state in Wearables.shared.registrationStateStream() {
            print("observeRegistrationState: received \(state)")
            registrationState = state
        }
        print("observeRegistrationState: stream ended")
    }

    private func observeDevices() async {
        print("observeDevices: starting to listen")
        for await devices in Wearables.shared.devicesStream() {
            print("observeDevices: received \(devices)")
            self.devices = devices
        }
        print("observeDevices: stream ended")
    }
}

// MARK: - Next steps (not implemented — verify current SDK API before building)
//
// Voice capture: DAT routes mic audio over Bluetooth HFP as raw 8kHz mono PCM
// (AVAudioEngine + installTap, per https://wearables.developer.meta.com/docs/develop/dat/microphones-and-speakers/).
// There's no built-in speech-to-text — captured buffers need to be forwarded to
// a transcription service (Whisper API, per your choice) before they're usable text.
//
// Obsidian write: once a transcript exists, write it into the vault via
// UIDocumentPicker + a security-scoped bookmark (the vault lives in iCloud Drive),
// or NSFileCoordinator for iCloud-safe appends to the Daily Note.
//
// Both need their own design pass — audio chunking/latency for the first,
// vault folder structure and Daily Note naming convention for the second.
