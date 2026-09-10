import SwiftUI
import SwiftData

struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    
    let notebooks: [NotebookModel]
    let sources: [SourceModel]
    var onClose: () -> Void
    
    @State private var query = ""
    @FocusState private var isFocused: Bool
    @State private var selection = 0
    
    private struct PaletteItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to a notebook, source, or command…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onChange(of: query) { selection = 0 }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                    .onKeyPress(.return) { runSelection(); return .handled }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
            
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No results for \"\(query)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == selection)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = index
                                    runSelection()
                                }
                        }
                    }
                    .padding(6)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                paletteHint("↑↓", "Navigate")
                paletteHint("⏎", "Open")
                paletteHint("Esc", "Close")
                Spacer()
                Text("\(filteredItems.count) matches")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 540, height: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2))
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .onAppear {
            isFocused = true
        }
    }
    
    private func paletteHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.tertiary)
        }
    }
    
    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
    
    private var baseItems: [PaletteItem] {
        var items: [PaletteItem] = []
        
        items.append(PaletteItem(
            title: "New Notebook",
            subtitle: "Create a new research notebook",
            icon: "books.vertical",
            action: {
                onClose()
                NotificationCenter.default.post(name: .createNotebook, object: nil)
            }
        ))
        items.append(PaletteItem(
            title: "Add Source",
            subtitle: "Website, files, or pasted text",
            icon: "plus.circle",
            action: {
                onClose()
                NotificationCenter.default.post(name: .addSource, object: nil)
            }
        ))
        items.append(PaletteItem(
            title: "Open Settings",
            subtitle: "AI providers, search, privacy, appearance",
            icon: "gearshape",
            action: {
                onClose()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        ))
        
        items.append(PaletteItem(
            title: "Research",
            subtitle: "Ask questions about your sources",
            icon: "bubble.left.and.bubble.right",
            action: {
                appState.centerTab = "research"
                onClose()
            }
        ))
        items.append(PaletteItem(
            title: "Study Tools",
            subtitle: "Summaries, quizzes, flashcards, and more",
            icon: "checklist",
            action: {
                appState.centerTab = "study"
                onClose()
            }
        ))
        items.append(PaletteItem(
            title: "Notes",
            subtitle: "Saved study tools and notes",
            icon: "note.text",
            action: {
                appState.centerTab = "notes"
                onClose()
            }
        ))
        
        for notebook in notebooks {
            items.append(PaletteItem(
                title: notebook.title,
                subtitle: notebook.subtitle.isEmpty ? "Open notebook" : notebook.subtitle,
                icon: "book",
                action: {
                    appState.selectedNotebookID = notebook.id
                    appState.centerTab = "sources"
                    onClose()
                    NotificationCenter.default.post(name: .selectNotebook, object: notebook.id)
                }
            ))
        }
        
        for source in sources {
            items.append(PaletteItem(
                title: source.title,
                subtitle: source.sourceType.displayName,
                icon: source.sourceType.icon,
                action: {
                    appState.selectedSourceID = source.id
                    appState.rightPanelTab = .source
                    appState.centerTab = "sources"
                    onClose()
                }
            ))
        }
        
        return items
    }
    
    private var filteredItems: [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return baseItems }
        let needle = trimmed.lowercased()
        return baseItems.filter {
            $0.title.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle)
        }
    }
    
    private func moveSelection(_ delta: Int) {
        guard !filteredItems.isEmpty else { return }
        selection = (selection + delta + filteredItems.count) % filteredItems.count
    }
    
    private func runSelection() {
        guard !filteredItems.isEmpty else { return }
        selection = min(max(selection, 0), filteredItems.count - 1)
        filteredItems[selection].action()
    }
}