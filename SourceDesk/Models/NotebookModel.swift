import Foundation
import SwiftData

@Model
final class NotebookModel {
    var id: UUID
    var title: String
    var subtitle: String
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var accentColor: String
    var tags: [String]
    
    @Relationship(deleteRule: .cascade, inverse: \SourceModel.notebook)
    var sources: [SourceModel]?
    
    @Relationship(deleteRule: .cascade, inverse: \ChatSessionModel.notebook)
    var chatSessions: [ChatSessionModel]?
    
    @Relationship(deleteRule: .cascade, inverse: \NotebookNoteModel.notebook)
    var notes: [NotebookNoteModel]?
    
    init(title: String, subtitle: String = "") {
        self.id = UUID()
        self.title = title
        self.subtitle = subtitle
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = false
        self.accentColor = "blue"
        self.tags = []
    }
    
    var sourceCount: Int {
        sources?.count ?? 0
    }
    
    var sortedSources: [SourceModel] {
        (sources ?? []).sorted { $0.addedAt > $1.addedAt }
    }
    
    var sortedNotes: [NotebookNoteModel] {
        (notes ?? []).sorted { $0.createdAt > $1.createdAt }
    }
}
