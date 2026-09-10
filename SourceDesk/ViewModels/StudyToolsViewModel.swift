import Foundation
import SwiftData
import Combine

@MainActor
final class StudyToolsViewModel: ObservableObject {
    @Published var notebook: NotebookModel?
    @Published var selectedTool: StudyToolType = .summary
    @Published var selectedSourceIDs: Set<UUID> = []
    @Published var outputText = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    
    private let aiManager: AIManager
    private let ragPipeline: RAGPipeline
    private let service: StudyToolsService
    private var context: ModelContext?
    
    init(aiManager: AIManager, ragPipeline: RAGPipeline) {
        self.aiManager = aiManager
        self.ragPipeline = ragPipeline
        self.service = StudyToolsService(aiManager: aiManager, ragPipeline: ragPipeline)
    }
    
    func configure(context: ModelContext) {
        self.context = context
    }
    
    var selectedSources: [SourceModel] {
        guard let notebook else { return [] }
        if selectedSourceIDs.isEmpty {
            return notebook.sortedSources
        }
        return notebook.sources?.filter { selectedSourceIDs.contains($0.id) } ?? []
    }
    
    var canGenerate: Bool {
        !isGenerating && !selectedSources.isEmpty
    }
    
    func generate() async {
        guard let notebook, canGenerate else {
            if selectedSources.isEmpty {
                errorMessage = "No sources available. Add sources to the notebook first."
            }
            return
        }
        
        let localOnlyMode = UserDefaults.standard.bool(forKey: "localOnlyMode")
        if localOnlyMode && !aiManager.selectedProvider.isLocal {
            errorMessage = "Local-Only Mode is enabled. Study tools require switching to a local model (Ollama), or disable Local-Only Mode in Settings."
            return
        }
        
        isGenerating = true
        errorMessage = nil
        outputText = ""
        
        do {
            outputText = try await service.generate(
                tool: selectedTool,
                notebook: notebook,
                sources: selectedSources
            )
        } catch {
            let aiError = error as? AIError
            errorMessage = aiError?.errorDescription ?? error.localizedDescription
            if let suggestion = aiError?.recoverySuggestion {
                errorMessage?.append("\n\n\(suggestion)")
            }
        }
        
        isGenerating = false
    }
    
    func saveToNotebook() {
        guard let context, let notebook, !outputText.isEmpty else { return }
        service.saveResult(outputText, toolType: selectedTool, into: notebook, context: context)
        outputText = ""
    }
    
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }
    
    func clear() {
        outputText = ""
        errorMessage = nil
    }
}