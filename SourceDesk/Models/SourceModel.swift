import Foundation
import SwiftData

enum SourceType: String, Codable, CaseIterable {
    case website = "website"
    case pdf = "pdf"
    case text = "text"
    case markdown = "markdown"
    case docx = "docx"
    case html = "html"
    case copiedText = "copiedText"
    case folder = "folder"
    
    var displayName: String {
        switch self {
        case .website: return "Website"
        case .pdf: return "PDF Document"
        case .text: return "Text File"
        case .markdown: return "Markdown"
        case .docx: return "Word Document"
        case .html: return "HTML"
        case .copiedText: return "Copied Text"
        case .folder: return "Folder"
        }
    }
    
    var icon: String {
        switch self {
        case .website: return "globe"
        case .pdf: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .markdown: return "doc.text"
        case .docx: return "doc.badge.gearshape"
        case .html: return "code"
        case .copiedText: return "clipboard"
        case .folder: return "folder"
        }
    }
}

enum SourceStatus: String, Codable {
    case pending = "pending"
    case downloading = "downloading"
    case processing = "processing"
    case indexing = "indexing"
    case ready = "ready"
    case error = "error"
    case incomplete = "incomplete"
}

@Model
final class SourceModel {
    var id: UUID
    var title: String
    var sourceType: SourceType
    var status: SourceStatus
    var url: String?
    var localFilePath: String?
    var rawContent: String?
    var extractedText: String?
    var errorMessage: String?
    var metadata: SourceMetadata
    var addedAt: Date
    var processedAt: Date?
    var isFavorite: Bool
    var wordCount: Int
    var chunkCount: Int
    var tags: [String]
    var lastAccessedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \SourceChunkModel.source)
    var chunks: [SourceChunkModel]?
    
    @Relationship(deleteRule: .nullify)
    var notebook: NotebookModel?
    
    @Relationship(deleteRule: .cascade, inverse: \EmbeddingModel.source)
    var embeddings: [EmbeddingModel]?
    
    init(title: String, type: SourceType) {
        self.id = UUID()
        self.title = title
        self.sourceType = type
        self.status = .pending
        self.metadata = SourceMetadata()
        self.addedAt = Date()
        self.isFavorite = false
        self.wordCount = 0
        self.chunkCount = 0
        self.tags = []
    }
    
    var displayURL: String {
        guard let url = url else { return localFilePath ?? "Local file" }
        return url
    }
    
    var hasContent: Bool {
        extractedText != nil && !(extractedText?.isEmpty ?? true)
    }
    
    var sortedChunks: [SourceChunkModel] {
        (chunks ?? []).sorted { $0.chunkIndex < $1.chunkIndex }
    }
}

struct SourceMetadata: Codable {
    var author: String?
    var publishedDate: String?
    var description: String?
    var mimeType: String?
    var fileSize: Int64?
    var pageCount: Int?
    var language: String?
    var favicon: String?
    var siteName: String?
    
    init() {}
}

@Model
final class SourceChunkModel {
    var id: UUID
    var content: String
    var chunkIndex: Int
    var startOffset: Int
    var endOffset: Int
    var pageNumber: Int?
    var headingContext: String?
    var tokenCount: Int
    
    @Relationship(deleteRule: .nullify)
    var source: SourceModel?
    
    init(content: String, index: Int, startOffset: Int, endOffset: Int) {
        self.id = UUID()
        self.content = content
        self.chunkIndex = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.tokenCount = content.split(separator: " ").count
    }
}

@Model
final class EmbeddingModel {
    var id: UUID
    var vector: Data
    var model: String
    var createdAt: Date
    
    @Relationship(deleteRule: .nullify)
    var source: SourceModel?
    
    @Relationship(deleteRule: .nullify)
    var chunk: SourceChunkModel?
    
    init(vector: Data, model: String) {
        self.id = UUID()
        self.vector = vector
        self.model = model
        self.createdAt = Date()
    }
    
    var vectorArray: [Float] {
        vector.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }
}
