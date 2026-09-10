import Foundation

struct RAGContext: Codable {
    var chunks: [RAGChunkContext]
    var webResults: [SearchResult] = []
    
    struct RAGChunkContext: Codable, Identifiable {
        var id: UUID
        var chunkID: UUID
        var sourceID: UUID
        var sourceTitle: String
        var content: String
        var pageNumber: Int?
        var url: String?
        
        init(chunk: RetrievedChunk) {
            self.id = UUID()
            self.chunkID = chunk.chunkID
            self.sourceID = chunk.sourceID
            self.sourceTitle = chunk.sourceTitle
            self.content = chunk.content
            self.pageNumber = chunk.pageNumber
            self.url = chunk.url
        }
    }
}

@MainActor
final class RAGPipeline {
    private let vectorStore: VectorStore
    private let aiManager: AIManager
    private let searchManager: SearchManager
    
    private var userDefaults = UserDefaults.standard
    
    var retrievalCount: Int {
        let saved = userDefaults.integer(forKey: "retrievalCount")
        return saved > 0 ? saved : 8
    }
    
    var chunkSize: Int {
        let saved = userDefaults.integer(forKey: "chunkSize")
        return saved > 0 ? saved : 800
    }
    
    init(vectorStore: VectorStore, aiManager: AIManager, searchManager: SearchManager) {
        self.vectorStore = vectorStore
        self.aiManager = aiManager
        self.searchManager = searchManager
    }
    
    func retrieve(query: String, in notebook: NotebookModel, searchMode: AppState.SearchMode) async throws -> RAGContext {
        var context = RAGContext(chunks: [], webResults: [])
        
        switch searchMode {
        case .notebookOnly:
            let chunks = try await vectorStore.semanticSearch(query: query, in: notebook, limit: retrievalCount)
            context.chunks = chunks.map(RAGContext.RAGChunkContext.init)
            
        case .notebookAndWeb:
            let chunks = try await vectorStore.semanticSearch(query: query, in: notebook, limit: max(retrievalCount / 2, 3))
            context.chunks = chunks.map(RAGContext.RAGChunkContext.init)
            
            if let webResults = try? await searchManager.search(query: query, maxResults: 5) {
                context.webResults = webResults
            }
            
        case .webOnly:
            if let webResults = try? await searchManager.search(query: query, maxResults: 8) {
                context.webResults = webResults
            }
        }
        
        return context
    }
    
    func buildSystemPrompt(context: RAGContext) -> String {
        var prompt = """
        You are an AI research assistant that helps users understand their sources.
        
        RULES:
        1. Answer primarily using the provided source material. Ground every claim in the sources when possible.
        2. When citing, use citation markers in the format [Source N] where N is the source number from the context.
        3. Never fabricate or hallucinate citations. Only cite sources that were actually provided.
        4. If the sources do not contain enough information, clearly say so and avoid speculating.
        5. Keep answers organized and readable.
        """
        
        if !context.chunks.isEmpty {
            prompt += "\n\n=== SOURCE MATERIAL ===\n"
            for (index, chunk) in context.chunks.enumerated() {
                prompt += "\n[Source \(index + 1)] \(chunk.sourceTitle)"
                if let page = chunk.pageNumber {
                    prompt += " (page \(page))"
                }
                if let url = chunk.url {
                    prompt += " — \(url)"
                }
                prompt += "\n\(chunk.content)\n"
            }
        } else {
            prompt += "\n\nNote: No source material was found in the notebook for this query."
        }
        
        if !context.webResults.isEmpty {
            prompt += "\n\n=== WEB SEARCH RESULTS ===\n"
            for (index, result) in context.webResults.enumerated() {
                prompt += "\n[Web \(index + 1)] \(result.title) — \(result.url)\n\(result.snippet)\n"
            }
            prompt += "\nWhen using web results, cite them as [Web N] and note they come from web search, not the user's sources."
        }
        
        return prompt
    }
    
    func chatSystemPrompt() -> String {
        return """
        You are an intelligent research assistant embedded within SourceDesk, a local-first research notebook.
        You are helping the user with their research.
        
        Guidelines:
        - When the user provides iterate with source material, answer based on it.
        - Prefer the user's own sources over general knowledge.
        - Be precise and well structured in your responses.
        - Note clearly when you're drawing from general knowledge rather than their sources.
        """
    }
}