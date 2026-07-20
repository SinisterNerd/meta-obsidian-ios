import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published var savedToObsidian = false

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func startRecording() async {
        errorMessage = nil
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)

            if let hfpInput = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
                try session.setPreferredInput(hfpInput)
            } else {
                errorMessage = "No Bluetooth HFP input found — is the glasses mic connected?"
            }
        } catch {
            errorMessage = "Audio session setup failed: \(error)"
            return
        }

        // Per Meta's docs: wait for the Bluetooth HFP route to stabilize before tapping.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        recordingURL = url

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            errorMessage = "Could not create audio file: \(error)"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        do {
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = "Engine start failed: \(error)"
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            transcript = try await WhisperClient.transcribe(fileURL: url)
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
    }
}
