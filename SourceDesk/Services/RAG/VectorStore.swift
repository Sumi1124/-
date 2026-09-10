import Foundation
import SwiftData

struct RetrievedChunk: Identifiable {
    let id: UUID
    let chunkID: UUID
    let sourceID: UUID
    let sourceTitle: String
    let content: String
    let score: Double
    let pageNumber: Int?
    let url: String?
    let sourceType: SourceType
    
    init(chunk: SourceChunkModel, source: SourceModel, score: Double) {
        self.id = UUID()
        self.chunkID = chunk.id
        self.sourceID = source.id
        self.sourceTitle = source.title
        self.content = chunk.content
        self.score = score
        self.pageNumber = chunk.pageNumber
        self.url = source.url
        self.sourceType = source.sourceType
    }
}

@MainActor
final class VectorStore {
    private let context: ModelContext
    private let aiManager: AIManager
    
    init(context: ModelContext, aiManager: AIManager) {
        self.context = context
        self.aiManager = aiManager
    }
    
    var useEmbeddings: Bool {
        UserDefaults.standard.bool(forKey: "useEmbeddings")
    }
    
    func semanticSearch(query: String, in notebook: NotebookModel, limit: Int = 8) async throws -> [RetrievedChunk] {
        guard useEmbeddings else {
            return keywordSearch(query: query, in: notebook, limit: limit)
        }
        
        do {
            let embeddingProvider: AIProvider
            
            if aiManager.ollama.selectedModel?.supportsEmbeddings == true {
                embeddingProvider = aiManager.ollama
            } else if aiManager.openai.selectedModel?.id.contains("embedding") == true {
                embeddingProvider = aiManager.openai
            } else if !(aiManager.openai.apiKey?.isEmpty ?? true) {
                embeddingProvider = aiManager.openai
            } else {
                return keywordSearch(query: query, in: notebook, limit: limit)
            }
            
            let queryVector = try await embeddingProvider.embed(text: query)
            guard queryVector.count > 0 else {
                return keywordSearch(query: query, in: notebook, limit: limit)
            }
            
            var results: [RetrievedChunk] = []
            
            for source in notebook.sources ?? [] {
                guard let chunks = source.chunks, !chunks.isEmpty else { continue }
                
                for chunk in chunks {
                    guard let embeddingModel = source.embeddings?.first(where: { $0.chunk?.id == chunk.id }) else {
                        continue
                    }
                    
                    let vector = embeddingModel.vectorArray
                    if vector.count > 0 {
                        let score = VectorMath.cosineSimilarity(queryVector, vector)
                        if score > 0.0 {
                            results.append(RetrievedChunk(chunk: chunk, source: source, score: score))
                        }
                    }
                }
            }
            
            return results
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { $0 }
        } catch {
            return keywordSearch(query: query, in: notebook, limit: limit)
        }
    }
    
    func keywordSearch(query: String, in notebook: NotebookModel, limit: Int = 8) -> [RetrievedChunk] {
        let keywords = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
        
        guard !keywords.isEmpty else { return [] }
        
        var results: [RetrievedChunk] = []
        var scores: [UUID: Double] = [:]
        
        for source in notebook.sources ?? [] {
            guard let chunks = source.chunks, !chunks.isEmpty, let text = source.extractedText else { continue }
            
            let textLower = text.lowercased()
            let textFrequency = keywords.reduce(0) { total, keyword in
                total + (textLower.contains(keyword) ? 1 : 0)
            }
            let textBoost = 1.0 + (Double(textFrequency) * 0.1)
            
            for chunk in chunks {
                let chunkLower = chunk.content.lowercased()
                var score = 0.0
                
                for keyword in keywords {
                    if chunkLower.contains(keyword) {
                        score += 1.0
                        
                        let occurrences = chunkLower.count(of: keyword)
                        score += Double(min(occurrences, 3)) * 0.3
                    }
                }
                
                if score > 0 {
                    let boosted = score * textBoost
                    results.append(RetrievedChunk(chunk: chunk, source: source, score: boosted))
                    scores[chunk.id] = boosted
                }
            }
        }
        
        return results
            .sorted { ($0.score) > ($1.score) }
            .prefix(limit)
            .map { $0 }
    }
}

extension String {
    func count(of substring: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        var count = 0
        var searchRange = startIndex..<endIndex
        while let foundRange = range(of: substring, options: [], range: searchRange) {
            count += 1
            searchRange = foundRange.upperBound..<endIndex
        }
        return count
    }
}