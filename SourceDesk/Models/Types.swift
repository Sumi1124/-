import Foundation

enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

struct Citation: Codable, Identifiable {
    var id: UUID
    var sourceTitle: String
    var sourceID: UUID
    var chunkID: UUID?
    var excerpt: String
    var pageNumber: Int?
    var url: String?
    var citationIndex: Int

    init(sourceTitle: String, sourceID: UUID, chunkID: UUID? = nil, excerpt: String, pageNumber: Int? = nil, url: String? = nil, citationIndex: Int) {
        self.id = UUID()
        self.sourceTitle = sourceTitle
        self.sourceID = sourceID
        self.chunkID = chunkID
        self.excerpt = excerpt
        self.pageNumber = pageNumber
        self.url = url
        self.citationIndex = citationIndex
    }
}