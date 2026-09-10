import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var container = ServiceContainer()
    
    @State private var showNewNotebookDialog = false
    @State private var showAddSourceDialog = false
    @State private var showCommandPalette = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                notebooksVM: container.notebookVM,
                onNewNotebook: { showNewNotebookDialog = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } content: {
            CenterPanelView(
                container: container,
                appState: appState,
                onAddSource: { showAddSourceDialog = true }
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 480, max: 800)
        } detail: {
            if let sourceVM = container.sourceVM, let chatVM = container.chatVM {
                InspectorPanelView(
                    sourceVM: sourceVM,
                    chatVM: chatVM,
                    aiManager: appState.aiManager,
                    appState: appState
                )
                .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 500)
            } else {
                Color.clear
            }
        }
        .toolbar {
            ToolbarView(aiManager: appState.aiManager, appState: appState)
        }
        .onAppear {
            configureServices()
            setupNotificationObservers()
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
        .sheet(isPresented: $showNewNotebookDialog) {
            NewNotebookSheet { title, subtitle in
                container.notebookVM?.createNotebook(title: title, subtitle: subtitle)
                if let notebook = container.notebookVM?.notebooks.first {
                    selectNotebook(notebook)
                }
            }
        }
        .sheet(isPresented: $showAddSourceDialog) {
            if let sourceVM = container.sourceVM {
                AddSourceSheet(sourceVM: sourceVM)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteChatMessage)) { note in
            guard let messageID = note.object as? UUID else { return }
            container.chatVM.deleteMessage(withID: messageID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
            showCommandPalette.toggle()
        }
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }
                        .onKeyPress(.escape) { showCommandPalette = false; return .handled }
                    
                    CommandPaletteView(
                        notebooks: container.notebookVM?.notebooks ?? [],
                        sources: container.sourceVM?.sources ?? [],
                        onClose: { showCommandPalette = false }
                    )
                    .environmentObject(appState)
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
    }
    
    private func configureServices() {
        container.configure(
            modelContext: modelContext,
            aiManager: appState.aiManager,
            searchManager: appState.searchManager
        )
        
        if let notebook = container.notebookVM?.notebooks.first {
            selectNotebook(notebook)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .createNotebook,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showNewNotebookDialog = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .addSource,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showAddSourceDialog = true
        }
        
        NotificationCenter.default.addObserver(
            forName: .selectNotebook,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let id = note.object as? UUID,
               let found = self.container.notebookVM?.notebooks.first(where: { $0.id == id }) {
                self.selectNotebook(found)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .notebookCreated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let notebook = note.object as? NotebookModel else { return }
            self.selectNotebook(notebook)
        }
    }
    
    private func selectNotebook(_ notebook: NotebookModel) {
        container.selectNotebook(notebook, modelContext: modelContext)
    }
}

@MainActor
final class ServiceContainer: ObservableObject {
    var embeddingService: EmbeddingService?
    var sourceVM: SourceViewModel?
    var notebookVM: NotebookViewModel?
    var chatVM: ChatViewModel?
    var ragPipeline: RAGPipeline?
    var studyToolsVM: StudyToolsViewModel?
    var exporter: NotebookExporter?
    
    var isReady: Bool {
        sourceVM != nil && notebookVM != nil && chatVM != nil
    }
    
    func configure(
        modelContext: ModelContext,
        aiManager: AIManager,
        searchManager: SearchManager
    ) {
        let ingestionService = SourceIngestionService()
        let chunkingService = ChunkingService()
        embeddingService = EmbeddingService(aiManager: aiManager)
        
        sourceVM = SourceViewModel(
            ingestionService: ingestionService,
            chunkingService: chunkingService,
            embeddingService: embeddingService
        )
        
        notebookVM = NotebookViewModel()
        notebookVM.configure(context: modelContext)
        
        ragPipeline = RAGPipeline(
            vectorStore: VectorStore(context: modelContext, aiManager: aiManager),
            aiManager: aiManager,
            searchManager: searchManager
        )
        
        chatVM = ChatViewModel(aiManager: aiManager, ragPipeline: ragPipeline, searchManager: searchManager)
        studyToolsVM = StudyToolsViewModel(aiManager: aiManager, ragPipeline: ragPipeline)
        exporter = NotebookExporter()
    }
    
    func selectNotebook(_ notebook: NotebookModel, modelContext: ModelContext) {
        sourceVM?.configure(context: modelContext, notebook: notebook)
        chatVM?.configure(context: modelContext, notebook: notebook)
        studyToolsVM?.notebook = notebook
        studyToolsVM?.configure(context: modelContext)
    }
}