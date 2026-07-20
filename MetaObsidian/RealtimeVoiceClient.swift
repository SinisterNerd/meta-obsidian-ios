import Foundation
import AVFoundation

// Bidirectional voice conversation over OpenAI's Realtime API. Streams glasses mic
// audio out over a WebSocket, plays the model's spoken reply back through the
// glasses speaker, and accumulates both sides' text transcripts.
//
// Protocol notes, confirmed on-device (not just from docs):
// - Mic audio streaming works — server-side VAD (input_audio_buffer.speech_started/
//   stopped) correctly detects real speech in our resampled 8kHz->24kHz PCM16 audio.
// - response.output_audio_transcript.delta correctly accumulates the assistant's
//   spoken reply as text.
// - session.audio.input/output.format must be an object — {"type": "audio/pcm",
//   "rate": 24000} — NOT a bare "pcm16" string. Sending it wrong doesn't kill the
//   connection, it just silently rejects the whole session.update (including
//   instructions and transcription config) while the session keeps running on
//   defaults, which is a confusing failure mode to debug from behavior alone.
//
// NOT yet confirmed: the event name/shape for the *user's* transcribed speech —
// transcription was never actually enabled in the one real test run so far (the
// format bug above blocked the session.update that would've turned it on).
// "conversation.item.input_audio_transcription.completed" is still just a guess.
// Any event type we don't recognize gets printed, so the next on-device test
// should reveal the real name if this guess is wrong.
//
// Also unconfirmed: whether playback audio is actually audible through the
// glasses speaker (no errors during conversion, but that doesn't prove it's heard).
@MainActor
final class RealtimeVoiceClient: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isResponding = false
    @Published var userTranscript = ""
    @Published var assistantTranscript = ""
    @Published var errorMessage: String?

    var onConversationEnded: ((_ userTranscript: String, _ assistantTranscript: String) -> Void)?

    private let realtimeSampleRate: Double = 24000
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var webSocketTask: URLSessionWebSocketTask?
    private var micConverter: AVAudioConverter?
    private var micSendFormat: AVAudioFormat?
    private var playbackSourceFormat: AVAudioFormat?
    private var playbackConverter: AVAudioConverter?
    private var playbackEngineFormat: AVAudioFormat?
    private var pendingPlaybackBuffers = 0
    private var awaitingPlaybackDrain = false

    func start() async {
        guard !isActive else { return }
        errorMessage = nil
        userTranscript = ""
        assistantTranscript = ""
        pendingPlaybackBuffers = 0
        awaitingPlaybackDrain = false

        guard
            let apiKey = Bundle.main.object(forInfoDictionaryKey: "AssistantAPIKey") as? String,
            !apiKey.isEmpty,
            apiKey != "your-assistant-api-key"
        else {
            errorMessage = "Missing Assistant API key"
            return
        }

        do {
            try BluetoothAudioSession.configure()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        try? await Task.sleep(nanoseconds: BluetoothAudioSession.routeStabilizationDelayNanoseconds)

        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        isActive = true
        listenForServerEvents()
        sendSessionUpdate()
        startAudioIO()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        stopAudioIO()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        onConversationEnded?(userTranscript, assistantTranscript)
    }

    // MARK: - WebSocket

    private func sendSessionUpdate() {
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "instructions": "You are a concise voice assistant speaking through smart glasses. Keep answers short.",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": realtimeSampleRate],
                        "transcription": ["model": "whisper-1"]
                    ],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": realtimeSampleRate]
                    ]
                ]
            ]
        ]
        send(json: event)
    }

    private func send(json: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: json),
            let text = String(data: data, encoding: .utf8)
        else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("RealtimeVoiceClient send error: \(error)")
            }
        }
    }

    private func listenForServerEvents() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        self.handleServerEvent(text)
                    }
                    if self.isActive {
                        self.listenForServerEvents()
                    }
                case .failure(let error):
                    print("RealtimeVoiceClient receive error: \(error)")
                    self.errorMessage = "Connection error: \(error.localizedDescription)"
                    self.stop()
                }
            }
        }
    }

    private func handleServerEvent(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        switch type {
        case "response.output_audio.delta":
            if let b64 = json["delta"] as? String, let audioData = Data(base64Encoded: b64) {
                playAudio(pcm16Data: audioData)
            }
        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                assistantTranscript += delta
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                userTranscript += transcript
            }
        case "response.created":
            isResponding = true
        case "response.done":
            // Don't tear down immediately — the model can finish generating (and
            // finish sending transcript deltas) before the audio already queued in
            // the player has actually finished playing. Wait for playback to drain.
            isResponding = false
            awaitingPlaybackDrain = true
            finishIfPlaybackDrained()
        case "error":
            print("RealtimeVoiceClient server error event: \(json)")
            if let errorInfo = json["error"] as? [String: Any], let message = errorInfo["message"] as? String {
                errorMessage = "Realtime error: \(message)"
            }
        default:
            print("RealtimeVoiceClient unhandled event type: \(type) — \(json)")
        }
    }

    // MARK: - Mic capture -> input_audio_buffer.append

    private func startAudioIO() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: realtimeSampleRate, channels: 1, interleaved: true) else {
            errorMessage = "Could not create mic send format"
            return
        }
        micSendFormat = sendFormat
        micConverter = AVAudioConverter(from: inputFormat, to: sendFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndSendMicBuffer(buffer, from: inputFormat)
        }

        guard let playbackSource = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: realtimeSampleRate, channels: 1, interleaved: true) else {
            errorMessage = "Could not create playback source format"
            return
        }
        playbackSourceFormat = playbackSource

        engine.attach(playerNode)
        if let engineFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: realtimeSampleRate, channels: 1, interleaved: false) {
            engine.connect(playerNode, to: engine.mainMixerNode, format: engineFormat)
            playbackEngineFormat = engineFormat
            playbackConverter = AVAudioConverter(from: playbackSource, to: engineFormat)
        }

        do {
            try engine.start()
            playerNode.play()
        } catch {
            errorMessage = "Engine start failed: \(error)"
        }
    }

    private func stopAudioIO() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(playerNode)
        engine.detach(playerNode)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convertAndSendMicBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat) {
        guard let converter = micConverter, let targetFormat = micSendFormat else { return }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

        var consumed = false
        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let convError {
            print("Mic conversion error: \(convError)")
            return
        }

        guard let channelData = outputBuffer.int16ChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0 else { return }
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)

        send(json: ["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
    }

    // MARK: - Playback

    private func playAudio(pcm16Data: Data) {
        guard
            let sourceFormat = playbackSourceFormat,
            let converter = playbackConverter,
            let destFormat = playbackEngineFormat
        else { return }

        let frameCount = pcm16Data.count / MemoryLayout<Int16>.size
        guard frameCount > 0, let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)

        pcm16Data.withUnsafeBytes { rawBuffer in
            guard
                let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                let dst = sourceBuffer.int16ChannelData?[0]
            else { return }
            dst.update(from: src, count: frameCount)
        }

        guard let destBuffer = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: AVAudioFrameCount(frameCount) + 16) else { return }

        var consumed = false
        var convError: NSError?
        converter.convert(to: destBuffer, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        if let convError {
            print("Playback conversion error: \(convError)")
            return
        }

        pendingPlaybackBuffers += 1
        // .dataPlayedBack (not the default .dataConsumed) is required here — the
        // default fires as soon as the buffer is handed to the mixer, not when it's
        // actually finished being audibly rendered, which would defeat the point.
        playerNode.scheduleBuffer(destBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingPlaybackBuffers -= 1
                self.finishIfPlaybackDrained()
            }
        }
    }

    private func finishIfPlaybackDrained() {
        guard awaitingPlaybackDrain, pendingPlaybackBuffers <= 0 else { return }
        awaitingPlaybackDrain = false
        stop()
    }
}
