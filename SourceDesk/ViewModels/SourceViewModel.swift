import Foundation
import SwiftData
import Combine

@MainActor
final class SourceViewModel: ObservableObject {
    @Published var sources: [SourceModel] = []
    @Published var selectedSourceID: UUID?
    @Published var searchText = ""
    @Published var isProcessing = false
    @Published var processingMessage: String?
    @Published var ingestionErrors: [SourceError] = []
    
    private var context: ModelContext?
    private(set) var notebook: NotebookModel?
    private let ingestionService: SourceIngestionService
    private let chunkingService: ChunkingService
    private let embeddingService: EmbeddingService
    private var processingTask: Task<Void, Never>?
    private var processingID = UUID()
    
    struct SourceError: Identifiable {
        let id = UUID()
        let message: String
        let sourceTitle: String
    }
    
    init(
        ingestionService: SourceIngestionService,
        chunkingService: ChunkingService,
        embeddingService: EmbeddingService
    ) {
        self.ingestionService = ingestionService
        self.chunkingService = chunkingService
        self.embeddingService = embeddingService
    }
    
    var filteredSources: [SourceModel] {
        guard !searchText.isEmpty else { return sources }
        return sources.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.url?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    func configure(context: ModelContext, notebook: NotebookModel?) {
        self.context = context
        self.notebook = notebook
        loadSources()
    }
    
    func loadSources() {
        guard let notebook else {
            sources = []
            return
        }
        sources = notebook.sortedSources
    }
    
    func addFromURL(_ urlString: String) {
        guard let context, let notebook else { return }
        beginProcessing("Downloading and processing \(urlString)...")
        let opID = processingID
        
        processingTask = Task { @MainActor in
            defer { finishProcessing(for: opID) }
            do {
                let source = try await ingestionService.ingest(urlString: urlString, into: notebook, context: context)
                guard !Task.isCancelled else {
                    ingestionService.deleteSource(source, context: context)
                    return
                }
                
                if source.status == .error {
                    ingestionErrors.append(SourceError(
                        message: source.errorMessage ?? "Unknown error",
                        sourceTitle: source.title
                    ))
                } else {
                    await processReadySource(source, context: context)
                }
            }
        }
    }
    
    func addFromFiles(urls: [URL]) {
        guard let context, let notebook else { return }
        beginProcessing("Processing files...")
        let opID = processingID
        
        processingTask = Task { @MainActor in
            defer { finishProcessing(for: opID) }
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                processingMessage = "Processing \(url.lastPathComponent) (\(index + 1)/\(urls.count))..."
                
                do {
                    let source = try await ingestionService.ingest(fileURL: url, into: notebook, context: context)
                    guard !Task.isCancelled else {
                        ingestionService.deleteSource(source, context: context)
                        break
                    }
                    
                    if source.status == .error {
                        ingestionErrors.append(SourceError(
                            message: source.errorMessage ?? "Unknown error",
                            sourceTitle: source.title
                        ))
                    } else {
                        await processReadySource(source, context: context)
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    ingestionErrors.append(SourceError(
                        message: error.localizedDescription,
                        sourceTitle: url.lastPathComponent
                    ))
                }
            }
        }
    }
    
    func addFromText(_ text: String, title: String) {
        guard let context, let notebook else { return }
        beginProcessing("Adding text source...")
        let opID = processingID
        
        processingTask = Task { @MainActor in
            defer { finishProcessing(for: opID) }
            do {
                let source = try await ingestionService.ingestText(
                    text: text,
                    title: title,
                    into: notebook,
                    context: context
                )
                guard !Task.isCancelled else {
                    ingestionService.deleteSource(source, context: context)
                    return
                }
                
                try? chunkingService.processSource(source, context: context)
                if embeddingService.shouldUseEmbeddings {
                    try? await embeddingService.embedChunks(in: source, context: context)
                }
                source.status = .ready
                try? context.save()
            }
        }
    }
    
    func reprocessSource(_ source: SourceModel) {
        guard let context else { return }
        beginProcessing("Reprocessing \(source.title)...")
        let opID = processingID
        
        processingTask = Task { @MainActor in
            defer { finishProcessing(for: opID) }
            guard !Task.isCancelled else { return }
            try? chunkingService.processSource(source, context: context)
            if embeddingService.shouldUseEmbeddings {
                try? await embeddingService.embedChunks(in: source, context: context)
            }
            source.status = .ready
            source.errorMessage = nil
            try? context.save()
        }
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingMessage = "Cancelling..."
    }
    
    func clearErrors() {
        ingestionErrors.removeAll()
    }
    
    private func beginProcessing(_ message: String) {
        processingTask?.cancel()
        processingID = UUID()
        isProcessing = true
        processingMessage = message
    }
    
    private func finishProcessing(for id: UUID) {
        guard id == processingID else { return }
        isProcessing = false
        processingMessage = nil
        loadSources()
    }
    
    private func processReadySource(_ source: SourceModel, context: ModelContext) async {
        processingMessage = "Chunking \(source.title)..."
        try? chunkingService.processSource(source, context: context)
        processingMessage = "Generating embeddings for \(source.title)..."
        
        if embeddingService.shouldUseEmbeddings {
            try? await embeddingService.embedChunks(in: source, context: context)
        }
        
        source.status = source.status == .error ? .error : .ready
        try? context.save()
    }
    
    func deleteSource(_ source: SourceModel) {
        guard let context else { return }
        ingestionService.deleteSource(source, context: context)
        loadSources()
    }
    
    func toggleFavorite(_ source: SourceModel) {
        source.isFavorite.toggle()
        try? context?.save()
    }
}