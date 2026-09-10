import Foundation
import Combine

@MainActor
class AIManager: ObservableObject {
    @Published var ollama: OllamaProvider
    @Published var openai: OpenAIProvider
    @Published var anthropic: AnthropicProvider
    @Published var selectingProvider: AIProviderConfig = .ollama
    
    @Published var ollamaDiagnostic = OllamaDiagnostic()
    @Published var availableModelList: [AIModel] = []
    @Published var ollamaIsAvailable = false
    
    private let userDefaults = UserDefaults.standard
    
    var selectedProvider: AIProvider {
        switch selectingProvider {
        case .ollama: return ollama
        case .openai: return openai
        case .anthropic: return anthropic
        }
    }
    
    init() {
        self.ollama = OllamaProvider()
        self.openai = OpenAIProvider()
        self.anthropic = AnthropicProvider()
        
        restoreSelectedModels()
        refreshOllamaStatus()
    }
    
    var availableProviders: [AIProvider] {
        [ollama, openai, anthropic]
    }
    
    func refreshOllamaStatus() async {
        ollamaIsAvailable = await ollama.isAvailable
        ollamaDiagnostic = await ollama.diagnose()
        if ollamaIsAvailable {
            availableModelList = await ollama.availableModels
        }
    }
    
    func refreshOllamaStatus() {
        Task { await refreshOllamaStatus() }
    }
    
    func selectModel(_ model: AIModel) {
        switch model.provider {
        case "ollama":
            ollama.selectedModel = model
        case "openai":
            openai.selectedModel = model
        case "anthropic":
            anthropic.selectedModel = model
        default:
            break
        }
        saveSelectedModels()
    }
    
    var selectedModelName: String {
        switch selectingProvider {
        case .ollama:
            return ollama.selectedModel?.name ?? "No model selected"
        case .openai:
            return openai.selectedModel?.name ?? "No model selected"
        case .anthropic:
            return anthropic.selectedModel?.name ?? "No model selected"
        }
    }
    
    var selectedModelContextLength: Int? {
        switch selectingProvider {
        case .ollama:
            return ollama.selectedModel?.contextLength
        case .openai:
            return openai.selectedModel?.contextLength
        case .anthropic:
            return anthropic.selectedModel?.contextLength
        }
    }
    
    private func saveSelectedModels() {
        if let m = ollama.selectedModel {
            userDefaults.set(m.id, forKey: "selectedModelOllama")
        }
        if let m = openai.selectedModel {
            userDefaults.set(m.id, forKey: "selectedModelOpenAI")
        }
        if let m = anthropic.selectedModel {
            userDefaults.set(m.id, forKey: "selectedModelAnthropic")
        }
    }
    
    private func restoreSelectedModels() {
        if let id = userDefaults.string(forKey: "selectedModelOllama") {
            ollama.selectedModel = AIModel(id: id, name: id, provider: "ollama", isLocal: true)
        }
        if let id = userDefaults.string(forKey: "selectedModelOpenAI") {
            openai.selectedModel = Self.openAIModels.first { $0.id == id }
        }
        if let id = userDefaults.string(forKey: "selectedModelAnthropic") {
            anthropic.selectedModel = Self.anthropicModels.first { $0.id == id }
        }
    }
    
    static let openAIModels = [
        AIModel(id: "gpt-4o", name: "GPT-4o", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", provider: "openai", contextLength: 128000, isLocal: false),
        AIModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", provider: "openai", contextLength: 16385, isLocal: false),
    ]
    
    static let anthropicModels = [
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", provider: "anthropic", contextLength: 200000, isLocal: false),
        AIModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", provider: "anthropic", contextLength: 200000, isLocal: false),
    ]
}