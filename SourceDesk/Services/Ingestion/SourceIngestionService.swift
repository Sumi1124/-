import Foundation
import SwiftData

@MainActor
@Observable
final class SourceIngestionService {
    private let webDownloader = WebDownloader()
    private let contentExtractor = ContentExtractor()
    private let documentExtractor = DocumentExtractor()
    private let fileManager = FileManager.default
    
    var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SourceDesk").appendingPathComponent("sources")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var activeIngestions: [UUID] = []
    
    func ingest(
        urlString: String,
        into notebook: NotebookModel,
        context: ModelContext
    ) async throws -> SourceModel {
        let source = SourceModel(title: urlString, type: .website)
        source.url = urlString
        source.status = .downloading
        notebook.sources?.append(source)
        context.insert(source)
        try? context.save()
        activeIngestions.append(source.id)
        
        defer { activeIngestions.removeAll { $0 == source.id } }
        
        do {
            let content = try await webDownloader.download(urlString: urlString)
            
            source.url = content.finalURL.absoluteString
            source.metadata.mimeType = content.mimeType
            source.status = .processing
            
            let title = await contentExtractor.extractTitle(from: content.html)
                ?? content.finalURL.host
            source.title = title
            
            let description = await contentExtractor.extractMetaDescription(from: content.html)
            source.metadata.description = description
            source.metadata.siteName = content.finalURL.host
            
            let text = await contentExtractor.extractMainContent(from: content.html)
            guard !text.isEmpty else {
                source.status = .error
                source.errorMessage = "No readable content could be extracted from this page. It may be JavaScript-heavy or empty."
                try? context.save()
                return source
            }
            
            source.extractedText = text
            source.rawContent = text
            source.wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
            source.status = .indexing
            
            try saveLocalContent(text, for: source)
            
            try? context.save()
            return source
        } catch {
            source.status = .error
            source.errorMessage = error.localizedDescription
            try? context.save()
            return source
        }
    }
    
    func ingest(
        fileURL: URL,
        into notebook: NotebookModel,
        context: ModelContext
    ) async throws -> SourceModel {
        let fileExtension = fileURL.pathExtension.lowercased()
        let type: SourceType
        
        switch fileExtension {
        case "pdf":
            type = .pdf
        case "txt", "text":
            type = .text
        case "md", "markdown":
            type = .markdown
        case "docx":
            type = .docx
        case "html", "htm":
            type = .html
        default:
            type = .text
        }
        
        let source = SourceModel(title: fileURL.deletingPathExtension().lastPathComponent, type: type)
        source.status = .processing
        source.localFilePath = fileURL.path
        notebook.sources?.append(source)
        context.insert(source)
        try? context.save()
        activeIngestions.append(source.id)
        
        defer { activeIngestions.removeAll { $0 == source.id } }
        
        do {
            let document: ExtractedDocument
            if fileExtension == "pdf" {
                document = try documentExtractor.extractPDF(from: fileURL)
            } else {
                document = try await documentExtractor.extractTextFile(from: fileURL)
            }
            
            source.title = document.title
            source.extractedText = document.text
            source.wordCount = document.text.split(whereSeparator: { $0.isWhitespace }).count
            source.metadata.author = document.author
            source.metadata.pageCount = document.pageCount
            source.metadata.fileSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? nil
            source.status = .indexing
            
            let storageURL = storageDirectory.appendingPathComponent(source.id.uuidString).appendingPathExtension(fileExtension)
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            try fileManager.copyItem(at: fileURL, to: tempURL)
            try? fileManager.removeItem(at: storageURL)
            try fileManager.moveItem(at: tempURL, to: storageURL)
            source.localFilePath = storageURL.path
            
            try? context.save()
            return source
        } catch {
            source.status = .error
            source.errorMessage = error.localizedDescription
            try? context.save()
            return source
        }
    }
    
    func ingestText(text: String, title: String, into notebook: NotebookModel, context: ModelContext) async throws -> SourceModel {
        let source = SourceModel(title: title, type: .copiedText)
        source.status = .processing
        notebook.sources?.append(source)
        context.insert(source)
        activeIngestions.append(source.id)
        
        defer { activeIngestions.removeAll { $0 == source.id } }
        
        let document = documentExtractor.extractFromString(text, title: title)
        source.extractedText = document.text
        source.rawContent = document.text
        source.wordCount = document.text.split(whereSeparator: { $0.isWhitespace }).count
        source.status = .indexing
        
        try? context.save()
        return source
    }
    
    private func saveLocalContent(_ text: String, for source: SourceModel) throws {
        let dir = storageDirectory
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let fileName = source.id.uuidString + ".txt"
        let fileURL = dir.appendingPathComponent(fileName)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        source.localFilePath = fileURL.path
    }
    
    func loadLocalContent(for source: SourceModel) -> String? {
        if let extracted = source.extractedText, !extracted.isEmpty {
            return extracted
        }
        
        guard let path = source.localFilePath, fileManager.fileExists(atPath: path) else {
            return nil
        }
        
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
    
    func deleteSource(_ source: SourceModel, context: ModelContext) {
        if let path = source.localFilePath {
            try? fileManager.removeItem(atPath: path)
        }
        
        for chunk in source.chunks ?? [] {
            context.delete(chunk)
        }
        for embedding in source.embeddings ?? [] {
            context.delete(embedding)
        }
        context.delete(source)
        try? context.save()
    }
}