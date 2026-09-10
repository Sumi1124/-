import Foundation
import SwiftData
import Combine

@MainActor
final class NotebookViewModel: ObservableObject {
    @Published var notebooks: [NotebookModel] = []
    @Published var selectedNotebookID: UUID?
    @Published var searchText = ""
    
    private var context: ModelContext?
    
    var filteredNotebooks: [NotebookModel] {
        guard !searchText.isEmpty else { return notebooks }
        return notebooks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    init() {}
    
    func configure(context: ModelContext) {
        self.context = context
        loadNotebooks()
    }
    
    func loadNotebooks() {
        guard let context else { return }
        let descriptor = FetchDescriptor<NotebookModel>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        notebooks = (try? context.fetch(descriptor)) ?? []
    }
    
    func createNotebook(title: String, subtitle: String = "") {
        guard let context else { return }
        let notebook = NotebookModel(title: title, subtitle: subtitle)
        context.insert(notebook)
        try? context.save()
        loadNotebooks()
        
        NotificationCenter.default.post(name: .notebookCreated, object: notebook)
    }
    
    func deleteNotebook(_ notebook: NotebookModel) {
        guard let context else { return }
        context.delete(notebook)
        try? context.save()
        loadNotebooks()
    }
    
    func renameNotebook(_ notebook: NotebookModel, title: String) {
        notebook.title = title
        notebook.modifiedAt = Date()
        try? context?.save()
        loadNotebooks()
    }
    
    func toggleFavorite(_ notebook: NotebookModel) {
        notebook.isFavorite.toggle()
        try? context?.save()
    }
    
    func recentNotebooks(limit: Int = 5) -> [NotebookModel] {
        Array(notebooks.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }
    
    func favoriteNotebooks() -> [NotebookModel] {
        notebooks.filter(\.isFavorite).sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

extension Notification.Name {
    static let notebookCreated = Notification.Name("notebookCreated")
}