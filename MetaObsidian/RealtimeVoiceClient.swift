import Foundation
import AVFoundation

// Bidirectional multi-turn voice conversation over OpenAI's Realtime API. Streams
// glasses mic audio out over a WebSocket, plays the model's spoken reply back
// through the glasses speaker, and accumulates a running multi-turn transcript.
// The session stays open across turns until a silence timeout or a stop phrase
// ends the conversation, at which point the full transcript is handed back via
// onConversationEnded.
//
// Protocol notes, confirmed on-device (not just from docs):
// - Mic audio streaming works — server-side VAD (input_audio_buffer.speech_started/
//   stopped) correctly detects real speech in our resampled 8kHz->24kHz PCM16 audio.
// - response.output_audio_transcript.delta correctly accumulates the assistant's
//   spoken reply as text.
// - conversation.item.input_audio_transcription.completed correctly delivers the
//   user's transcribed speech (there's also a .delta variant we don't need).
// - session.audio.input/output.format must be an object — {"type": "audio/pcm",
//   "rate": 24000} — NOT a bare "pcm16" string. Sending it wrong doesn't kill the
//   connection, it just silently rejects the whole session.update (including
//   instructions and transcription config) while the session keeps running on
//   defaults, which is a confusing failure mode to debug from behavior alone.
// - response.done can fire before queued audio has actually finished playing —
//   must wait for playback to drain (.dataPlayedBack completion) before treating
//   a turn as finished, or replies get audibly cut off.
@MainActor
final class RealtimeVoiceClient: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isResponding = false
    @Published var currentUserTurn = ""
    @Published var currentAssistantTurn = ""
    @Published var conversationTranscript = ""
    @Published var errorMessage: String?

    var onConversationEnded: ((_ transcript: String) -> Void)?

    // TODO: make stop phrases configurable too
    var stopPhrases = ["stop", "that's all", "that is all", "goodbye", "end conversation"]
    var silenceTimeoutSeconds: TimeInterval = SettingsKeys.defaultSilenceTimeoutSeconds

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
    private var conversationShouldEndAfterThisTurn = false
    private var silenceTimer: DispatchWorkItem?

    func start() async {
        guard !isActive else { return }
        errorMessage = nil
        currentUserTurn = ""
        currentAssistantTurn = ""
        conversationTranscript = ""
        pendingPlaybackBuffers = 0
        awaitingPlaybackDrain = false
        conversationShouldEndAfterThisTurn = false
        silenceTimer?.cancel()
        silenceTimer = nil
        let storedTimeout = UserDefaults.standard.double(forKey: SettingsKeys.silenceTimeoutSeconds)
        silenceTimeoutSeconds = storedTimeout > 0 ? storedTimeout : SettingsKeys.defaultSilenceTimeoutSeconds

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
        silenceTimer?.cancel()
        silenceTimer = nil
        stopAudioIO()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        onConversationEnded?(conversationTranscript)
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
        case "input_audio_buffer.speech_started":
            // User is talking again — cancel any pending end-of-conversation timeout.
            silenceTimer?.cancel()
            silenceTimer = nil
        case "response.output_audio.delta":
            if let b64 = json["delta"] as? String, let audioData = Data(base64Encoded: b64) {
                playAudio(pcm16Data: audioData)
            }
        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                currentAssistantTurn += delta
            }
        case "conversation.item.input_audio_transcription.delta":
            // The reliable source for the user's transcribed speech — .completed
            // (below) isn't guaranteed to arrive before the conversation ends.
            if let delta = json["delta"] as? String {
                currentUserTurn += delta
                if containsStopPhrase(currentUserTurn) {
                    conversationShouldEndAfterThisTurn = true
                }
            }
        case "conversation.item.input_audio_transcription.completed":
            // When it does arrive, it's the authoritative full transcript for the
            // turn (not incremental) — replace, don't append, or we'd duplicate
            // whatever the .delta events above already accumulated.
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                currentUserTurn = transcript
                if containsStopPhrase(transcript) {
                    conversationShouldEndAfterThisTurn = true
                }
            }
        case "response.created":
            isResponding = true
            // Belt-and-suspenders alongside the speech_started cancellation below —
            // if the model is actively responding, the conversation obviously isn't
            // silent, regardless of what triggered this response.
            silenceTimer?.cancel()
            silenceTimer = nil
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

    private func containsStopPhrase(_ transcript: String) -> Bool {
        let lowered = transcript.lowercased()
        return stopPhrases.contains { lowered.contains($0) }
    }

    // MARK: - Turn / conversation lifecycle

    private func finishIfPlaybackDrained() {
        guard awaitingPlaybackDrain, pendingPlaybackBuffers <= 0 else { return }
        awaitingPlaybackDrain = false
        handleTurnComplete()
    }

    private func handleTurnComplete() {
        conversationTranscript += "**You:** \(currentUserTurn)\n\n**Assistant:** \(currentAssistantTurn)\n\n"
        currentUserTurn = ""
        currentAssistantTurn = ""

        if conversationShouldEndAfterThisTurn {
            stop()
            return
        }

        scheduleSilenceTimeout()
    }

    private func scheduleSilenceTimeout() {
        silenceTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            print("RealtimeVoiceClient: silence timeout, ending conversation")
            self?.stop()
        }
        silenceTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeoutSeconds, execute: workItem)
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
}
