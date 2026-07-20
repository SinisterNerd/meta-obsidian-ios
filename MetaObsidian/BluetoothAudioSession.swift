import AVFoundation

enum BluetoothAudioSession {
    // Per Meta's docs: HFP microphone route needs a moment to stabilize before tapping.
    static let routeStabilizationDelayNanoseconds: UInt64 = 2_000_000_000

    static func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true)

        guard let hfpInput = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) else {
            throw BluetoothAudioSessionError.noHFPInput
        }
        try session.setPreferredInput(hfpInput)
    }
}

enum BluetoothAudioSessionError: LocalizedError {
    case noHFPInput

    var errorDescription: String? {
        "No Bluetooth HFP input found — is the glasses mic connected?"
    }
}
