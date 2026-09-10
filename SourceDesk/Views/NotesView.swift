import SwiftUI
import SwiftData

struct NotesView: View {
    var notebook: NotebookModel?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    
    @Query private var notes: [NotebookNoteModel]
    
    var body: some View {
        Group {
            if let notebook, notebook.notes?.isEmpty != false {
                Text("No notes in this notebook yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                notesList
            }
        }
        .onAppear { loadNotes() }
    }
    
    private var notesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(filteredNotes) { note in
                    NoteCardView(note: note)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(note.content, forType: .string)
                            }
                            Button("Delete") {
                                modelContext.delete(note)
                                try? modelContext.save()
                                loadNotes()
                            }
                        }
                }
            }
            .padding()
        }
    }
    
    private var filteredNotes: [NotebookNoteModel] {
        notes.filter { $0.notebook?.id == notebook?.id }
    }
    
    private func loadNotes() {
        // Query handles notification automatically
    }
}

struct NoteCardView: View {
    @Bindable var note: NotebookNoteModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                Spacer()
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Text(note.content)
                .font(.callout)
                .lineLimit(8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}