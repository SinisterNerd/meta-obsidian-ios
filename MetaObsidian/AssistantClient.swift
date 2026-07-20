import Foundation

enum AssistantClientError: LocalizedError {
    case missingAPIKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing Assistant API key — set ASSISTANT_API_KEY in config.xcconfig"
        case .badResponse(let body):
            return "Assistant API error: \(body)"
        }
    }
}

// Currently backed by OpenAI's chat completions endpoint. ASSISTANT_API_KEY is kept
// separate from WHISPER_API_KEY so a different provider (e.g. Claude) can replace
// this file later without touching config or the rest of the app.
enum AssistantClient {
    // Update to whatever current model you want to use.
    private static let model = "gpt-4o-mini"

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    static func ask(_ question: String) async throws -> String {
        guard
            let apiKey = Bundle.main.object(forInfoDictionaryKey: "AssistantAPIKey") as? String,
            !apiKey.isEmpty,
            apiKey != "your-assistant-api-key"
        else {
            throw AssistantClientError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatRequest(model: model, messages: [.init(role: "user", content: question)])
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AssistantClientError.badResponse(bodyText)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw AssistantClientError.badResponse("No choices returned")
        }
        return text
    }
}
