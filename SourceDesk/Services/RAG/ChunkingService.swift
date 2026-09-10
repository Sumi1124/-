import Foundation
import SwiftData

enum ChunkingError: LocalizedError {
    case noSources
    
    var errorDescription: String? {
        switch self {
        case .noSources:
            return "No sources are available to process."
        }
    }
}

@MainActor
final class ChunkingService {
    private var userDefaults = UserDefaults.standard
    
    var chunkSize: Int {
        get { userDefaults.integer(forKey: "chunkSize") > 0 ? userDefaults.integer(forKey: "chunkSize") : 800 }
        set { userDefaults.set(newValue, forKey: "chunkSize") }
    }
    
    var overlapTokens: Int {
        get { max(min(userDefaults.integer(forKey: "chunkOverlap"), 200), 0) }
        set { userDefaults.set(newValue, forKey: "chunkOverlap") }
    }
    
    @discardableResult
    func processSource(_ source: SourceModel, context: ModelContext) throws -> Int {
        guard let text = source.extractedText, !text.isEmpty else {
            throw ChunkingError.noSources
        }
        
        for chunk in source.chunks ?? [] {
            context.delete(chunk)
        }
        
        let chunked = try TextChunker.chunk(
            text: text,
            maxTokens: chunkSize,
            overlapTokens: overlapTokens
        )
        
        var storedChunks: [SourceChunkModel] = []
        for chunk in chunked {
            let chunkModel = SourceChunkModel(
                content: chunk.content,
                index: chunk.index,
                startOffset: chunk.startOffset,
                endOffset: chunk.endOffset
            )
            chunkModel.pageNumber = chunk.pageNumber
            chunkModel.source = source
            context.insert(chunkModel)
            storedChunks.append(chunkModel)
        }
        
        source.chunks = storedChunks
        source.chunkCount = storedChunks.count
        
        try context.save()
        return storedChunks.count
    }
    
    func processAllSources(in notebook: NotebookModel, context: ModelContext) async throws -> Int {
        var total = 0
        for source in notebook.sources ?? [] {
            guard let text = source.extractedText, !text.isEmpty else { continue }
            do {
                total += try processSource(source, context: context)
            } catch {
                source.status = .error
                source.errorMessage = "Failed to chunk source: \(error.localizedDescription)"
                try? context.save()
            }
        }
        return total
    }
}

enum EmbeddingError: LocalizedError {
    case noEmbeddingModel
    case embeddingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noEmbeddingModel:
            return "No embedding model is available. Install an embedding model in Ollama (e.g. 'ollama pull nomic-embed-text') or configure OpenAI embeddings."
        case .embeddingFailed(let reason):
            return "Embedding generation failed: \(reason)"
        }
    }
}

@MainActor
final class EmbeddingService {
    private let aiManager: AIManager
    
    init(aiManager: AIManager) {
        self.aiManager = aiManager
    }
    
    var shouldUseEmbeddings: Bool {
        UserDefaults.standard.bool(forKey: "useEmbeddings")
    }
    
    private func getEmbeddingProvider() throws -> AIProvider {
        if aiManager.ollama.selectedModel?.supportsEmbeddings == true {
            return aiManager.ollama
        }
        
        if aiManager.openai.selectedModel?.id.contains("embedding") == true {
            return aiManager.openai
        }
        
        if UserDefaults.standard.bool(forKey: "useOpenAIEmbeddings") && !(aiManager.openai.apiKey?.isEmpty ?? true) {
            let provider = aiManager.openai
            provider.selectedModel = AIModel(
                id: "text-embedding-3-small",
                name: "Embedding 3 Small",
                provider: "openai",
                isLocal: false,
                supportsEmbeddings: true
            )
            return provider
        }
        
        throw EmbeddingError.noEmbeddingModel
    }
    
    func embedChunks(in source: SourceModel, context: ModelContext) async throws -> Int {
        do {
            let provider = try getEmbeddingProvider()
            guard let chunks = source.chunks, !chunks.isEmpty else { return 0 }
            
            for embedding in source.embeddings ?? [] {
                context.delete(embedding)
            }
            source.embeddings = []
            
            var generated = 0
            for chunk in chunks {
                try Task.checkCancellation()
                do {
                    let vector = try await provider.embed(text: chunk.content)
                    let vectorData = vector.withUnsafeBufferPointer { buffer in
                        Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.stride)
                    }
                    let embedding = EmbeddingModel(vector: vectorData, model: provider.name)
                    embedding.source = source
                    embedding.chunk = chunk
                    context.insert(embedding)
                    source.embeddings?.append(embedding)
                    generated += 1
                } catch {
                    if chunk.chunkIndex == 0 {
                        throw error
                    }
                }
            }
            
            try context.save()
            return generated
        } catch EmbeddingError.noEmbeddingModel {
            source.status = .error
            source.errorMessage = "Embedding failed: no embedding model is available."
            try? context.save()
            throw error
        }
    }
}