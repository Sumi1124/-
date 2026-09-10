import Foundation

final class OllamaProvider: AIProvider {
    let name = "Ollama"
    let isLocal = true
    var selectedModel: AIModel?
    
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }
    
    var isAvailable: Bool {
        get async {
            guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
            do {
                let (_, response) = try await session.data(from: url)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
    
    var availableModels: [AIModel] {
        get async {
            guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
            do {
                let (data, _) = try await session.data(from: url)
                let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                return response.models.map { model in
                    let supportsEmbeddings = model.name.contains("embed") || model.name.contains("nomic")
                    return AIModel(
                        id: model.name,
                        name: model.name.replacingOccurrences(of: ":", with: " "),
                        provider: "ollama",
                        contextLength: nil,
                        isLocal: true,
                        supportsEmbeddings: supportsEmbeddings,
                        parameterSize: model.details?.parameterSize
                    )
                }
            } catch {
                return []
            }
        }
    }
    
    func generate(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> AIResponse {
        guard let modelID = selectedModel?.id else {
            throw AIError(kind: .notConfigured, message: "No Ollama model selected.", recoverySuggestion: "Select a model in Settings > AI Providers > Ollama. Models must be installed locally using 'ollama pull <model>' first.")
        }
        
        var ollamaMessages: [OllamaMessage] = []
        if let system = systemPrompt {
            ollamaMessages.append(OllamaMessage(role: "system", content: system))
        }
        for msg in messages {
            ollamaMessages.append(OllamaMessage(role: msg.role.rawValue, content: msg.content))
        }
        
        let body = OllamaGenerateRequest(
            model: modelID,
            messages: ollamaMessages,
            options: OllamaOptions(
                temperature: Float(temperature),
                num_predict: maxTokens
            ),
            stream: false
        )
        
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw AIError.connectionFailed(provider: name)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.connectionFailed(provider: name)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError(
                kind: .serverError(httpResponse.statusCode),
                message: "Ollama error: \(errorBody)",
                recoverySuggestion: "Check that Ollama is running and the model '\(modelID)' is available locally."
            )
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return AIResponse(
            content: ollamaResponse.message.content,
            model: modelID,
            provider: name,
            tokenCount: ollamaResponse.evalCount
        )
    }
    
    func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let modelID = self.selectedModel?.id else {
                    continuation.finish(throwing: AIError(
                        kind: .notConfigured,
                        message: "No Ollama model selected.",
                        recoverySuggestion: "Select a model in Settings > AI Providers > Ollama."
                    ))
                    return
                }
                
                var ollamaMessages: [OllamaMessage] = []
                if let system = systemPrompt {
                    ollamaMessages.append(OllamaMessage(role: "system", content: system))
                }
                for msg in messages {
                    ollamaMessages.append(OllamaMessage(role: msg.role.rawValue, content: msg.content))
                }
                
                let body = OllamaGenerateRequest(
                    model: modelID,
                    messages: ollamaMessages,
                    options: OllamaOptions(
                        temperature: Float(temperature),
                        num_predict: maxTokens
                    ),
                    stream: true
                )
                
                guard let url = URL(string: "\(self.baseURL)/api/chat") else {
                    continuation.finish(throwing: AIError.connectionFailed(provider: self.name))
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)
                
                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: AIError.connectionFailed(provider: self.name))
                        return
                    }
                    
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(OllamaStreamChunk.self, from: data)
                        continuation.yield(chunk.message.content)
                        if chunk.done {
                            break
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
        let models = await availableModels
        guard let embedModel = models.first(where: { $0.supportsEmbeddings }) else {
            throw AIError(
                kind: .notConfigured,
                message: "No embedding model found in Ollama.",
                recoverySuggestion: "Install an embedding model locally: ollama pull nomic-embed-text"
            )
        }
        
        let body: [String: Any] = [
            "model": embedModel.id,
            "input": text
        ]
        
        guard let url = URL(string: "\(baseURL)/api/embed") else {
            throw AIError.connectionFailed(provider: name)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OllamaEmbedResponse.self, from: data)
        return response.embeddings.first ?? []
    }
    
    func diagnose() async -> OllamaDiagnostic {
        var diagnostic = OllamaDiagnostic()
        
        let available = await isAvailable
        diagnostic.serverRunning = available
        
        if available {
            let models = await availableModels
            diagnostic.installedModels = models
            diagnostic.hasChatModel = models.contains { !$0.supportsEmbeddings }
            diagnostic.hasEmbeddingModel = models.contains { $0.supportsEmbeddings }
        }
        
        return diagnostic
    }
}

struct OllamaDiagnostic {
    var serverRunning: Bool = false
    var installedModels: [AIModel] = []
    var hasChatModel: Bool = false
    var hasEmbeddingModel: Bool = false
    
    var statusMessage: String {
        if !serverRunning {
            return "Ollama is not running. Start it with: ollama serve"
        }
        if installedModels.isEmpty {
            return "Ollama is running but no models are installed. Install models with: ollama pull <model-name>"
        }
        var parts: [String] = []
        if hasChatModel {
            parts.append("\(installedModels.filter { !$0.supportsEmbeddings }.count) chat model(s)")
        }
        if hasEmbeddingModel {
            parts.append("\(installedModels.filter { $0.supportsEmbeddings }.count) embedding model(s)")
        }
        return "Ollama running with \(parts.joined(separator: ", "))"
    }
}

// MARK: - Ollama API Models

private struct OllamaTagsResponse: Codable {
    let models: [OllamaModelInfo]
}

private struct OllamaModelInfo: Codable {
    let name: String
    let size: Int64?
    let details: OllamaModelDetails?
}

private struct OllamaModelDetails: Codable {
    let parameterSize: String?
    
    enum CodingKeys: String, CodingKey {
        case parameterSize = "parameter_size"
    }
}

private struct OllamaGenerateRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let options: OllamaOptions?
    let stream: Bool
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaOptions: Codable {
    let temperature: Float?
    let num_predict: Int?
}

private struct OllamaChatResponse: Codable {
    let message: OllamaMessage
    let evalCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case message
        case evalCount = "eval_count"
    }
}

private struct OllamaStreamChunk: Codable {
    let message: OllamaMessage
    let done: Bool
}

private struct OllamaEmbedResponse: Codable {
    let embeddings: [[Float]]
}
