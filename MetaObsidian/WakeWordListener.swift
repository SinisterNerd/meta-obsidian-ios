import Foundation
import Speech
import AVFoundation

// Continuous on-device wake-phrase detection. Interim approach while Picovoice's
// sales-gated signup is pending — costs more battery than a dedicated wake-word
// engine (SFSpeechRecognizer is a full speech model, not a tiny keyword spotter),
// but needs no external account and works today.
@MainActor
final class WakeWordListener: ObservableObject {
    @Published var isListening = false
    @Published var errorMessage: String?
    @Published var lastPartialTranscript = ""

    var wakePhrase = SettingsKeys.defaultWakePhrase
    var onWakeWordDetected: (() -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        wakePhrase = (UserDefaults.standard.string(forKey: SettingsKeys.wakePhrase) ?? SettingsKeys.defaultWakePhrase).lowercased()

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer unavailable"
            return
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            errorMessage = "Speech recognition not authorized — check Settings"
            return
        }

        do {
            try BluetoothAudioSession.configure()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isListening = true
        startRecognitionTask()
    }

    func stop() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isListening = false
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startRecognitionTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                errorMessage = "Engine start failed: \(error)"
                return
            }
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionUpdate(result: result, error: error)
            }
        }

        // SFSpeechRecognitionTask has a bounded max duration; restart periodically
        // to sustain effectively-continuous listening.
        scheduleRestart()
    }

    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString.lowercased()
            lastPartialTranscript = text
            if text.contains(wakePhrase) {
                stop()
                onWakeWordDetected?()
            }
        }
        if let error {
            print("WakeWordListener recognition error: \(error)")
        }
    }

    private func scheduleRestart() {
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restartRecognitionTask()
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 55, execute: workItem)
    }

    private func restartRecognitionTask() {
        guard isListening else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        startRecognitionTask()
    }
}
