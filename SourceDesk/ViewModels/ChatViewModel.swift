import Foundation
import SwiftData
import Combine

struct ChatError: LocalizedError {
    var message: String
    var suggestion: String?
    
    var errorDescription: String? { message }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var sessions: [ChatSessionModel] = []
    @Published var selectedSessionID: UUID?
    @Published var messages: [ChatMessageModel] = []
    @Published var isGenerating = false
    @Published var errors: [String] = []
    
    private var context: ModelContext?
    private(set) var notebook: NotebookModel?
    private let aiManager: AIManager
    private let ragPipeline: RAGPipeline
    private let searchManager: SearchManager
    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()
    
    init(aiManager: AIManager, ragPipeline: RAGPipeline, searchManager: SearchManager) {
        self.aiManager = aiManager
        self.ragPipeline = ragPipeline
        self.searchManager = searchManager
    }
    
    func configure(context: ModelContext, notebook: NotebookModel?) {
        self.context = context
        self.notebook = notebook
        loadSessions()
    }
    
    func loadSessions() {
        guard let context, let notebook else {
            sessions = []
            return
        }
        
        let descriptor = FetchDescriptor<ChatSessionModel>(
            predicate: #Predicate { $0.notebook?.id == notebook.id }
        )
        if let results = try? context.fetch(descriptor) {
            sessions = results.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        
        if let current = sessions.first(where: { $0.id == selectedSessionID }) {
            selectedSessionID = current.id
        } else {
            selectedSessionID = sessions.first?.id
        }
        loadMessages()
    }
    
    func newSession() {
        guard let context, let notebook else { return }
        
        let session = ChatSessionModel(title: "Chat \(Date().formatted(date: .abbreviated, time: .shortened))")
        session.notebook = notebook
        context.insert(session)
        try? context.save()
        
        loadSessions()
    }
    
    func selectSession(_ session: ChatSessionModel) {
        selectedSessionID = session.id
        loadMessages()
    }
    
    func deleteSession(_ session: ChatSessionModel) {
        guard let context else { return }
        context.delete(session)
        try? context.save()
        loadSessions()
    }
    
    func loadMessages() {
        guard let context, let selectedSessionID else {
            messages = []
            return
        }
        
        if let session = sessions.first(where: { $0.id == selectedSessionID }) {
            messages = session.sortedMessages
        } else {
            messages = []
        }
    }
    
    func sendMessage(_ text: String, searchMode: AppState.SearchMode, isOnline: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isGenerating,
              let context,
              let notebook,
              let session = sessions.first(where: { $0.id == selectedSessionID }) else {
            return
        }
        
        let localOnlyMode = UserDefaults.standard.bool(forKey: "localOnlyMode")
        let providerIsCloud = !aiManager.selectedProvider.isLocal
        let needsWeb = searchMode != .notebookOnly
        
        if localOnlyMode && (providerIsCloud || needsWeb) {
            let errorMessage = ChatMessageModel(role: .assistant, content: "**Local-Only Mode is enabled.** Cloud AI and web search are disabled.\n\nEnable them in Settings > Privacy, or switch to a local model (Ollama) to continue.")
            errorMessage.session = session
            errorMessage.isError = true
            errorMessage.provider = aiManager.selectedProvider.name
            context.insert(errorMessage)
            try? context.save()
            loadMessages()
            return
        }
        
        if !isOnline && providerIsCloud {
            let errorMessage = ChatMessageModel(role: .assistant, content: "**No internet connection.** Cloud AI providers are unavailable while offline.\n\nSwitch to a local model (Ollama) to keep using research chat, and review the current notebook from local storage.")
            errorMessage.session = session
            errorMessage.isError = true
            errorMessage.provider = aiManager.selectedProvider.name
            context.insert(errorMessage)
            try? context.save()
            loadMessages()
            return
        }
        
        let userMessage = ChatMessageModel(role: .user, content: text)
        userMessage.session = session
        context.insert(userMessage)
        try? context.save()
        
        session.modifiedAt = Date()
        
        let assistantMessage = ChatMessageModel(role: .assistant, content: "")
        assistantMessage.session = session
        assistantMessage.isStreaming = true
        context.insert(assistantMessage)
        try? context.save()
        
        messages = session.sortedMessages
        isGenerating = true
        
        let taskID = UUID()
        generationID = taskID
        generationTask = Task { @MainActor in
            defer {
                if generationID == taskID {
                    isGenerating = false
                    generationTask = nil
                    loadMessages()
                }
            }
            do {
                let ragContext = try await ragPipeline.retrieve(query: text, in: notebook, searchMode: searchMode)
                let systemPrompt = ragPipeline.buildSystemPrompt(context: ragContext)
                
                let priorMessages: [ChatMessage] = session.sortedMessages
                    .filter { !$0.isStreaming && !$0.content.isEmpty && $0.id != assistantMessage.id }
                    .suffix(20)
                    .map { ChatMessage(role: $0.role, content: $0.content) }
                
                let response = try await aiManager.selectedProvider.generate(
                    messages: priorMessages + [ChatMessage(role: .user, content: text)],
                    systemPrompt: systemPrompt,
                    temperature: 0.3,
                    maxTokens: 2048
                )
                
                let citations = parseCitations(from: response.content, using: ragContext)
                
                assistantMessage.content = response.content
                assistantMessage.isStreaming = false
                assistantMessage.model = response.model
                assistantMessage.provider = response.provider
                assistantMessage.citationsJSON = encodeCitations(citations)
                assistantMessage.searchMode = searchMode.rawValue
                
                session.modifiedAt = Date()
                try context.save()
            } catch is CancellationError {
                context.delete(assistantMessage)
                try? context.save()
            } catch {
                let aiError = error as? AIError
                assistantMessage.content = "**Error:** \(aiError?.message ?? error.localizedDescription)"
                if let suggestion = aiError?.recoverySuggestion {
                    assistantMessage.content += "\n\n> \(suggestion)"
                }
                assistantMessage.isStreaming = false
                assistantMessage.isError = true
                try? context.save()
            }
        }
    }
    
    func stopGenerating() {
        generationTask?.cancel()
        isGenerating = false
    }
    
    func parseCitations(from text: String, using ragContext: RAGContext) -> [Citation] {
        var citations: [Citation] = []
        
        let pattern = #"\[Source (\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        
        var seenIndices = Set<Int>()
        for match in matches {
            guard let indexRange = Range(match.range(at: 1), in: text),
                  let index = Int(text[indexRange]) else { continue }
            
            guard !seenIndices.contains(index) else { continue }
            seenIndices.insert(index)
            
            let chunkIndex = index - 1
            guard chunkIndex >= 0, chunkIndex < ragContext.chunks.count else { continue }
            
            let chunk = ragContext.chunks[chunkIndex]
            let excerpt = String(chunk.content.prefix(400))
            
            citations.append(Citation(
                sourceTitle: chunk.sourceTitle,
                sourceID: chunk.sourceID,
                chunkID: chunk.chunkID,
                excerpt: excerpt,
                pageNumber: chunk.pageNumber,
                url: chunk.url,
                citationIndex: index
            ))
        }
        
        return citations
    }
    
    private func encodeCitations(_ citations: [Citation]) -> String? {
        guard let data = try? JSONEncoder().encode(citations) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteMessage(_ message: ChatMessageModel) {
        guard let context else { return }
        context.delete(message)
        try? context.save()
        loadMessages()
    }
    
    func deleteMessage(withID id: UUID) {
        guard let context else { return }
        if let message = messages.first(where: { $0.id == id }) {
            context.delete(message)
            try? context.save()
            loadMessages()
        }
    }
}