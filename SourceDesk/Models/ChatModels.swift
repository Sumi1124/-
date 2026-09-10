import Foundation
import SwiftData

@Model
final class ChatSessionModel {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var searchMode: String
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageModel.session)
    var messages: [ChatMessageModel]?
    
    @Relationship(deleteRule: .nullify)
    var notebook: NotebookModel?
    
    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.searchMode = "notebookOnly"
    }
    
    var sortedMessages: [ChatMessageModel] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class ChatMessageModel {
    var id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date
    var model: String?
    var provider: String?
    var isStreaming: Bool
    var searchMode: String?
    var citationsJSON: String?
    var tokenCount: Int
    var isError: Bool
    
    @Relationship(deleteRule: .nullify)
    var session: ChatSessionModel?
    
    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.isStreaming = false
        self.tokenCount = content.split(separator: " ").count
        self.isError = false
    }
    
    var citations: [Citation] {
        guard let json = citationsJSON else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Citation].self, from: data)) ?? []
    }
    
    func setCitations(_ citations: [Citation]) {
        guard let data = try? JSONEncoder().encode(citations) else { return }
        self.citationsJSON = String(data: data, encoding: .utf8)
    }
}

@Model
final class NotebookNoteModel {
    var id: UUID
    var title: String
    var content: String
    var noteType: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var sourceReferences: [String]
    
    @Relationship(deleteRule: .nullify)
    var notebook: NotebookModel?
    
    init(title: String, content: String, type: String = "note") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.noteType = type
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isPinned = false
        self.sourceReferences = []
    }
}
