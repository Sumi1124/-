import Foundation

final class OpenAIProvider: AIProvider {
    let name = "OpenAI"
    let isLocal = false
    var selectedModel: AIModel?
    
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let keychainService = KeychainService()
    
    var apiKey: String? {
        get { keychainService.getPassword(service: "sourcedesk", account: "openai") }
        set {
            if let key = newValue {
                keychainService.setPassword(key, service: "sourcedesk", account: "openai")
            } else {
                keychainService.deletePassword(service: "sourcedesk", account: "openai")
            }
        }
    }
    
    private static let availableModelsList: [AIModel] = [
        AIModel(id: "gpt-4o", name: "GPT-4o", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: "openai", contextLength: 16385, isLocal: false),
        AIModel(id: "text-embedding-3-large", name: "Embedding 3 Large", provider: "openai", contextLength: nil, isLocal: false, supportsEmbeddings: true),
        AIModel(id: "text-embedding-3-small", name: "Embedding 3 Small", provider: "openai", contextLength: nil, isLocal: false, supportsEmbeddings: true),
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
            guard let url = URL(string: "\(baseURL)/models") else { return false }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await session.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
    
    var availableModels: [AIModel] {
        get async {
            guard let key = apiKey, !key.isEmpty else { return Self.availableModelsList }
            guard let url = URL(string: "\(baseURL)/models") else { return Self.availableModelsList }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (data, _) = try await session.data(for: request)
                let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                let modelIDs = Set(response.data.map(\.id))
                return Self.availableModelsList.filter { modelIDs.contains($0.id) }
            } catch {
                return Self.availableModelsList
            }
        }
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
        
        let modelID = selectedModel?.id ?? "gpt-4o"
        
        var openAIMessages: [[String: String]] = []
        if let system = systemPrompt {
            openAIMessages.append(["role": "system", "content": system])
        }
        for msg in messages {
            openAIMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        
        let body: [String: Any] = [
            "model": modelID,
            "messages": openAIMessages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw AIError.connectionFailed(provider: name)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed(provider: name)
        }
        
        switch httpResponse.statusCode {
        case 200:
            let completion = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)
            let content = completion.choices.first?.message?.content ?? ""
            return AIResponse(
                content: content,
                model: modelID,
                provider: name,
                tokenCount: completion.usage?.totalTokens
            )
        case 401:
            throw AIError.missingAPIKey(provider: name)
        case 429:
            throw AIError(kind: .rateLimited, message: "OpenAI rate limit exceeded.", recoverySuggestion: "Wait a moment and try again, or reduce request frequency.")
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError(kind: .serverError(httpResponse.statusCode), message: "OpenAI error (\(httpResponse.statusCode)): \(errorBody)")
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
                
                let modelID = self.selectedModel?.id ?? "gpt-4o"
                
                var openAIMessages: [[String: String]] = []
                if let system = systemPrompt {
                    openAIMessages.append(["role": "system", "content": system])
                }
                for msg in messages {
                    openAIMessages.append(["role": msg.role.rawValue, "content": msg.content])
                }
                
                let body: [String: Any] = [
                    "model": modelID,
                    "messages": openAIMessages,
                    "temperature": temperature,
                    "max_tokens": maxTokens,
                    "stream": true
                ]
                
                guard let url = URL(string: "\(self.baseURL)/chat/completions") else {
                    continuation.finish(throwing: AIError.connectionFailed(provider: self.name))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
                        guard jsonStr != "[DONE]" else { break }
                        
                        guard let data = jsonStr.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta.content else {
                            continue
                        }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func embed(text: String) async throws -> [Float] {
        guard let key = apiKey, !key.isEmpty else {
            throw AIError.missingAPIKey(provider: name)
        }
        
        let modelID = selectedModel?.id ?? "text-embedding-3-small"
        
        let body: [String: Any] = [
            "model": modelID,
            "input": text
        ]
        
        guard let url = URL(string: "\(baseURL)/embeddings") else {
            throw AIError.connectionFailed(provider: name)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OpenAIEmbeddingResponse.self, from: data)
        return response.data.first?.embedding ?? []
    }
}

// MARK: - OpenAI API Models

private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModelEntry]
}

private struct OpenAIModelEntry: Codable {
    let id: String
}

private struct OpenAICompletionResponse: Codable {
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Codable {
    let message: OpenAIChatMessage?
    let delta: OpenAIChatMessage?
}

private struct OpenAIChatMessage: Codable {
    let role: String?
    let content: String?
}

private struct OpenAIUsage: Codable {
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
    }
}

private struct OpenAIStreamChunk: Codable {
    let choices: [OpenAIStreamChoice]
}

private struct OpenAIStreamChoice: Codable {
    let delta: OpenAIChatMessage
}

private struct OpenAIEmbeddingResponse: Codable {
    let data: [OpenAIEmbeddingData]
}

private struct OpenAIEmbeddingData: Codable {
    let embedding: [Float]
}
