import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published var savedToObsidian = false
    @Published var assistantReply = ""
    @Published var isAsking = false

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func startRecording() async {
        errorMessage = nil
        transcript = ""
        assistantReply = ""
        savedToObsidian = false

        do {
            try BluetoothAudioSession.configure()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        try? await Task.sleep(nanoseconds: BluetoothAudioSession.routeStabilizationDelayNanoseconds)

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

    func askAssistant() async {
        guard !transcript.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            assistantReply = try await AssistantClient.ask(transcript)
        } catch {
            errorMessage = "Assistant failed: \(error.localizedDescription)"
        }
    }
}
