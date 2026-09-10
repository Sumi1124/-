import Foundation

final class AnthropicProvider: AIProvider {
    let name = "Anthropic"
    let isLocal = false
    var selectedModel: AIModel?
    
    private let baseURL = "https://api.anthropic.com/v1"
    private let session: URLSession
    private let keychainService = KeychainService()
    
    var apiKey: String? {
        get { keychainService.getPassword(service: "sourcedesk", account: "anthropic") }
        set {
            if let key = newValue {
                keychainService.setPassword(key, service: "sourcedesk", account: "anthropic")
            } else {
                keychainService.deletePassword(service: "sourcedesk", account: "anthropic")
            }
        }
    }
    
    private static let availableModelsList: [AIModel] = [
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", provider: "anthropic", contextLength: 200000, isLocal: false),
    ]
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }
    
    var isAvailable: Bool {
        get async {
            guard let key = apiKey, !key.isEmpty else { return false }
            return true
        }
    }
    
    var availableModels: [AIModel] {
        Self.availableModelsList
    }
    
    func generate(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> AIResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw AIError.missingAPIKey(provider: name)
        }
        
        let modelID = selectedModel?.id ?? "claude-sonnet-4-20250514"
        
        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        
        if let system = systemPrompt {
            body["system"] = system
        }
        
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw AIError.connectionFailed(provider: name)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed(provider: name)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
            let content = result.content.compactMap(\.text).joined(separator: "\n")
            return AIResponse(
                content: content,
                model: modelID,
                provider: name,
                tokenCount: (result.usage?.inputTokens ?? 0) + (result.usage?.outputTokens ?? 0)
            )
        case 401:
            throw AIError.missingAPIKey(provider: name)
        case 429:
            throw AIError(kind: .rateLimited, message: "Anthropic rate limit exceeded.", recoverySuggestion: "Wait a moment and try again.")
        case 400:
            let errorBody = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)
            throw AIError(kind: .invalidResponse, message: errorBody?.error.message ?? "Invalid request to Anthropic.")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError(kind: .serverError(httpResponse.statusCode), message: "Anthropic error (\(httpResponse.statusCode)): \(errorBody)")
        }
    }
    
    func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let key = self.apiKey, !key.isEmpty else {
                    continuation.finish(throwing: AIError.missingAPIKey(provider: self.name))
                    return
                }
                
                let modelID = self.selectedModel?.id ?? "claude-sonnet-4-20250514"
                
                var body: [String: Any] = [
                    "model": modelID,
                    "max_tokens": maxTokens,
                    "temperature": temperature,
                    "stream": true,
                    "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                ]
                
                if let system = systemPrompt {
                    body["system"] = system
                }
                
                guard let url = URL(string: "\(self.baseURL)/messages") else {
                    continuation.finish(throwing: AIError.connectionFailed(provider: self.name))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: AIError.connectionFailed(provider: self.name))
                        return
                    }
                    
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let jsonStr = String(trimmed.dropFirst(6))
                        
                        guard let data = jsonStr.data(using: .utf8) else { continue }
                        
                        if let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = event["type"] as? String {
                            if type == "content_block_delta",
                               let delta = event["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            } else if type == "message_stop" {
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func embed(text: String) async throws -> [Float] {
        throw AIError(kind: .notConfigured, message: "Anthropic does not provide an embedding API.", recoverySuggestion: "Use OpenAI or Ollama for embeddings instead.")
    }
}

// MARK: - Anthropic API Models

private struct AnthropicMessageResponse: Codable {
    let content: [AnthropicContentBlock]
    let usage: AnthropicUsage?
}

private struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

private struct AnthropicUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

private struct AnthropicErrorResponse: Codable {
    let error: AnthropicErrorDetail
}

private struct AnthropicErrorDetail: Codable {
    let type: String
    let message: String
}
