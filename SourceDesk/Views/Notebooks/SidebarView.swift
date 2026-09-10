import SwiftUI
import SwiftData

struct SidebarView: View {
    @ObservedObject var notebooksVM: NotebookViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var onNewNotebook: () -> Void
    
    var body: some View {
        List {
            Section {
                SidebarItemView(tab: .notebooks, icon: "books.vertical", title: "Notebooks")
                SidebarItemView(tab: .favorites, icon: "star", title: "Favorites")
                SidebarItemView(tab: .recent, icon: "clock", title: "Recent")
            }
            
            Section(sectionTitle) {
                if displayedNotebooks.isEmpty {
                    Text(sectionEmptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedNotebooks) { notebook in
                        NotebookSidebarRow(
                            notebook: notebook,
                            isSelected: appState.selectedNotebookID == notebook.id
                        )
                        .contextMenu {
                            Button("Rename…") { renameNotebook(notebook) }
                            Button("Export…") { exportNotebook(notebook) }
                            Divider()
                            if !notebook.isFavorite {
                                Button("Add to Favorites") { notebooksVM.toggleFavorite(notebook) }
                            } else {
                                Button("Remove from Favorites") { notebooksVM.toggleFavorite(notebook) }
                            }
                            Divider()
                            Button("Delete…", role: .destructive) { deleteNotebook(notebook) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $notebooksVM.searchText, placement: .sidebar, prompt: "Search notebooks")
        .navigationTitle("SourceDesk")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewNotebook()
                } label: {
                    Label("New Notebook", systemImage: "plus")
                }
                .help("New Notebook (⌘N)")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    importNotebook()
                } label: {
                    Label("Import Notebook", systemImage: "square.and.arrow.down")
                }
                .help("Import a notebook archive (.zip)")
            }
        }
    }
    
    private var sectionTitle: String {
        switch appState.selectedTab {
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        default: return "All Notebooks"
        }
    }
    
    private var displayedNotebooks: [NotebookModel] {
        switch appState.selectedTab {
        case .favorites: return notebooksVM.favoriteNotebooks()
        case .recent: return notebooksVM.recentNotebooks(limit: 10)
        default: return notebooksVM.filteredNotebooks
        }
    }
    
    private var sectionEmptyMessage: String {
        switch appState.selectedTab {
        case .favorites: return "No favorite notebooks yet. Use the context menu to favorite one."
        case .recent: return "No recent notebooks."
        default: return "No notebooks yet. Press ⌘N to create one."
        }
    }
    
    private func renameNotebook(_ notebook: NotebookModel) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = notebook.title
        
        let alert = NSAlert()
        alert.messageText = "Rename Notebook"
        alert.informativeText = "Enter a new name:"
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        
        if alert.runModal() == .alertFirstButtonReturn {
            notebooksVM.renameNotebook(notebook, title: field.stringValue)
        }
    }
    
    private func deleteNotebook(_ notebook: NotebookModel) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \"\(notebook.title)\"?"
        alert.informativeText = "This will delete the notebook. Source files associated with this notebook will also be deleted. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            notebooksVM.deleteNotebook(notebook)
        }
    }
    
    private func exportNotebook(_ notebook: NotebookModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(notebook.title).sourcedesk.zip"
        
        if panel.runModal() == .OK, let url = panel.url {
            let exporter = NotebookExporter()
            Task { @MainActor in
                do {
                    try await exporter.export(notebook: notebook, to: url)
                } catch {
                    presentError(error)
                }
            }
        }
    }
    
    private func importNotebook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        
        if panel.runModal() == .OK, let url = panel.url {
            let exporter = NotebookExporter()
            Task { @MainActor in
                do {
                    _ = try await exporter.importNotebook(from: url, into: modelContext)
                    notebooksVM.loadNotebooks()
                } catch {
                    presentError(error)
                }
            }
        }
    }
    
    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private struct SidebarItemView: View {
    let tab: AppState.SidebarTab
    let icon: String
    let title: String
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Button {
            if tab == .settings {
                presentSettings()
            } else {
                appState.selectedTab = tab
            }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.sidebarButton(isSelected: appState.selectedTab == tab))
    }
    
    private func presentSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct NotebookSidebarRow: View {
    let notebook: NotebookModel
    let isSelected: Bool
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Button {
            select()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconFor(notebook))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(notebook.title)
                        .lineLimit(1)
                    if !notebook.subtitle.isEmpty {
                        Text(notebook.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
                
                if notebook.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                
                Text("\(notebook.sourceCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .buttonStyle(.sidebarButton(isSelected: isSelected))
        .contextMenu {
            // Handled by parent
        }
    }
    
    private func iconFor(_ notebook: NotebookModel) -> String {
        switch notebook.sourceCount {
        case 0: return "book"
        case 1...10: return "book.fill"
        default: return "books.vertical.fill"
        }
    }
    
    private func select() {
        appState.selectedTab = .notebooks
        appState.selectedNotebookID = notebook.id
        NotificationCenter.default.post(name: .selectNotebook, object: notebook.id)
    }
}

extension ButtonStyle where Self == SidebarButtonStyle {
    static func sidebarButton(isSelected: Bool) -> SidebarButtonStyle {
        SidebarButtonStyle(isSelected: isSelected)
    }
}

struct SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}