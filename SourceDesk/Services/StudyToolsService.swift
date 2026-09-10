import Foundation
import SwiftData

enum StudyToolType: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case keyPoints = "Key Points"
    case timeline = "Timeline"
    case faq = "FAQ"
    case quiz = "Quiz"
    case flashcards = "Flashcards"
    case studyGuide = "Study Guide"
    case outline = "Outline"
    case quotes = "Quotations"
    case comparison = "Compare Sources"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .keyPoints: return "list.bullet"
        case .timeline: return "clock.arrow.circlepath"
        case .faq: return "questionmark.circle"
        case .quiz: return "checklist"
        case .flashcards: return "rectangle.stack"
        case .studyGuide: return "book.closed"
        case .outline: return "list.number"
        case .quotes: return "quote.opening"
        case .comparison: return "rectangle.split.2x1"
        }
    }
    
    var description: String {
        switch self {
        case .summary: return "Generate a concise overview of the selected sources"
        case .keyPoints: return "Extract the most important takeaways"
        case .timeline: return "Build a chronological timeline from the content"
        case .faq: return "Generate likely questions and answers"
        case .quiz: return "Create a practice quiz from the material"
        case .flashcards: return "Create flashcard pairs for active recall"
        case .studyGuide: return "Generate a structured study guide"
        case .outline: return "Create a hierarchical outline"
        case .quotes: return "Extract important, quotable passages"
        case .comparison: return "Compare two or more sources side by side"
        }
    }
}

@MainActor
final class StudyToolsService {
    private let aiManager: AIManager
    private let ragPipeline: RAGPipeline
    
    init(aiManager: AIManager, ragPipeline: RAGPipeline) {
        self.aiManager = aiManager
        self.ragPipeline = ragPipeline
    }
    
    func prompt(for tool: StudyToolType, notebook: NotebookModel, sources: [SourceModel], query: String? = nil) -> String {
        var sourceText = ""
        
        if !sources.isEmpty {
            sourceText = "=== SOURCE CONTENT ===\n"
            for (index, source) in sources.enumerated() {
                sourceText += "\n[Source \(index + 1)] \(source.title)\n"
                if let text = source.extractedText {
                    let truncated = String(text.prefix(12000))
                    sourceText += truncated + "\n"
                }
            }
        } else if let notebookText = notebook.sources?.compactMap(\.extractedText).flatMap({ $0 }).prefix(24000).map(String.init).joined(separator: "\n\n") {
            sourceText = "=== SOURCE CONTENT ===\n\(notebookText)"
        }
        
        let promptBody: String
        switch tool {
        case .summary:
            promptBody = """
            Generate a comprehensive but concise summary of the source material.
            Structure the summary with clear sections.
            Include the most important facts, figures, and arguments.
            """
        case .keyPoints:
            promptBody = """
            Extract the key points from the source material.
            Present them as a numbered list.
            Each point should be self-contained and precise.
            """
        case .timeline:
            promptBody = """
            Create a chronological timeline from the events discussed in the sources.
            Format as a list with dates or time periods first, followed by the event description.
            If dates are not explicit, estimate order based on the narrative.
            """
        case .faq:
            promptBody = """
            Generate an FAQ based on the source material.
            Ask the 8 most likely questions a student or researcher would ask about this material.
            Answer each question with grounding in the sources.
            """
        case .quiz:
            promptBody = """
            Create a practice quiz from the source material.
            Generate 8 questions with 4 multiple-choice options each and indicate the correct answer.
            Mark each correct answer clearly with \n\nAnswer: X at the end of each question.
            """
        case .flashcards:
            promptBody = """
            Create flashcards from the source material.
            For each card provide:
            - Front: a concept, term, or question
            - Back: the definition or answer
            Format each card as: Front: ... / Back: ...
            Generate 10 cards.
            """
        case .studyGuide:
            promptBody = """
            Create a structured study guide from the source material.
            Organize by themes or chapters with headings.
            Include key terminology, essential concepts, and review questions.
            """
        case .outline:
            promptBody = """
            Create a hierarchical outline of the source material.
            Use clear heading levels.
            Capture the logical structure and argument flow.
            """
        case .quotes:
            promptBody = """
            Extract the most important quotations from the source material.
            For each quote provide:
            - The exact quoted text
            - Why it's important
            - The source it comes from
            """
        case .comparison:
            promptBody = """
            Compare the source documents provided.
            Identify and present:
            - Overlapping themes
            - Key differences in approach or conclusion
            - Complementary information
            - Contradictions (if any)
            """
        }
        
        return """
        You are a research assistant generating study material.
        
        \(promptBody)
        
        \(sourceText)
        
        Base everything on the provided source content. Do not include facts not present in the sources.
        """
    }
    
    func generate(
        tool: StudyToolType,
        notebook: NotebookModel,
        sources: [SourceModel],
        query: String? = nil
    ) async throws -> String {
        let prompt = prompt(for: tool, notebook: notebook, sources: sources, query: query)
        
        let messages = [ChatMessage(role: .user, content: prompt)]
        
        let response = try await aiManager.selectedProvider.generate(
            messages: messages,
            systemPrompt: "You are a precise research assistant. Only use information found in the provided sources.",
            temperature: 0.3,
            maxTokens: 4000
        )
        
        return response.content
    }
    
    func saveResult(_ text: String, toolType: StudyToolType, into notebook: NotebookModel, context: ModelContext) {
        let note = NotebookNoteModel(
            title: "\(toolType.rawValue) — \(Date().formatted(date: .abbreviated, time: .shortened))",
            content: text,
            type: toolType.rawValue.lowercased()
        )
        note.notebook = notebook
        context.insert(note)
        try? context.save()
    }
}