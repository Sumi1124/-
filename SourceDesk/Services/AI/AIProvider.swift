import Foundation

// MARK: - AI Provider Protocol

protocol AIProvider: AnyObject {
    var name: String { get }
    var isLocal: Bool { get }
    var isAvailable: Bool { get async }
    var availableModels: [AIModel] { get async }
    var selectedModel: AIModel? { get set }
    
    func generate(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> AIResponse
    
    func stream(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
    
    func embed(text: String) async throws -> [Float]
}

struct AIModel: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var provider: String
    var contextLength: Int?
    var isLocal: Bool
    var supportsEmbeddings: Bool
    var parameterSize: String?
    
    init(id: String, name: String, provider: String, contextLength: Int? = nil, isLocal: Bool = false, supportsEmbeddings: Bool = false, parameterSize: String? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextLength = contextLength
        self.isLocal = isLocal
        self.supportsEmbeddings = supportsEmbeddings
        self.parameterSize = parameterSize
    }
}

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: MessageRole
    var content: String
    
    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

struct AIResponse: Codable {
    var content: String
    var model: String?
    var provider: String?
    var tokenCount: Int?
    var finishReason: String?
}

struct AIError: LocalizedError {
    enum ErrorKind {
        case notConfigured
        case connectionFailed
        case modelNotFound
        case rateLimited
        case contextTooLong
        case invalidResponse
        case providerUnavailable
        case missingAPIKey
        case quotaExceeded
        case networkError
        case serverError(Int)
        case unknown(String)
    }
    
    var kind: ErrorKind
    var message: String
    var recoverySuggestion: String?
    
    var errorDescription: String? { message }
    var failureReason: String? { recoverySuggestion }
    
    static func notConfigured(provider: String) -> AIError {
        AIError(kind: .notConfigured, message: "\(provider) is not configured.", recoverySuggestion: "Open Settings > AI Providers to configure \(provider).")
    }
    
    static func connectionFailed(provider: String) -> AIError {
        AIError(kind: .connectionFailed, message: "Could not connect to \(provider).", recoverySuggestion: "Check that the service is running and accessible.")
    }
    
    static func modelNotFound(model: String) -> AIError {
        AIError(kind: .modelNotFound, message: "Model '\(model)' was not found.", recoverySuggestion: "Check available models in Settings > AI Providers.")
    }
    
    static func missingAPIKey(provider: String) -> AIError {
        AIError(kind: .missingAPIKey, message: "No API key configured for \(provider).", recoverySuggestion: "Open Settings > AI Providers and enter your \(provider) API key.")
    }
    
    static func contextTooLong(limit: Int) -> AIError {
        AIError(kind: .contextTooLong, message: "The context exceeds the model's limit of \(limit) tokens.", recoverySuggestion: "Try using a larger context model or reduce the number of sources in your query.")
    }
    
    static func networkError(_ underlying: Error) -> AIError {
        AIError(kind: .networkError, message: "Network error: \(underlying.localizedDescription)", recoverySuggestion: "Check your internet connection.")
    }
    
    static func providerUnavailable(provider: String) -> AIError {
        AIError(kind: .providerUnavailable, message: "\(provider) is currently unavailable.", recoverySuggestion: "Try again later or switch to a different provider.")
    }
}
