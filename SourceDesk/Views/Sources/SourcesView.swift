import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @ObservedObject var sourceVM: SourceViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var onAddSource: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add…") {
                    onAddSource()
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            if sourceVM.isProcessing {
                ProcessingBannerView(
                    message: sourceVM.processingMessage ?? "Processing source...",
                    onCancel: { sourceVM.cancelProcessing() }
                )
                Divider()
            }
            
            if !sourceVM.ingestionErrors.isEmpty {
                IngestionErrorsBanner(errors: sourceVM.ingestionErrors) {
                    sourceVM.clearErrors()
                }
                Divider()
            }
            
            if sourceVM.sources.isEmpty {
                SourcesEmptyState(onAddSource: onAddSource)
            } else {
                sourceList
            }
        }
        .onChange(of: appState.selectedNotebookID) { _, _ in
            refreshSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNotebook)) { note in
            guard let _ = note.object as? UUID else { return }
            refreshSources()
        }
    }
    
    private var sourceList: some View {
        ScrollView {
            LazyVStack(spacing: 6, pinnedViews: []) {
                ForEach(sourceVM.filteredSources) { source in
                    SourceRowView(
                        source: source,
                        isSelected: appState.selectedSourceID == source.id
                    )
                    .onTapGesture {
                        appState.selectedSourceID = source.id
                        appState.rightPanelTab = .source
                    }
                    .contextMenu {
                        Button("Toggle Favorite") { sourceVM.toggleFavorite(source) }
                        Button("Reprocess") {
                            sourceVM.reprocessSource(source)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            sourceVM.deleteSource(source)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func refreshSources() {
        sourceVM.loadSources()
    }
}