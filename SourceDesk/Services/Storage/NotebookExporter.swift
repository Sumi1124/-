import Foundation
import SwiftData

enum ImportExportError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}

/// Exports and imports notebooks as a documented .zip archive.
///
/// Archive layout (`<notebook>.sourcedesk.zip`):
/// ```
/// Export-<UUID>/
/// ├── notebook.json      — manifest with notebook, sources, chats, notes
/// ├── sources/
/// │   ├── <sourceID>.<ext>
/// │   └── <sourceID>.json (metadata sidecar)
/// ```
@MainActor
final class NotebookExporter {
    private let fileManager = FileManager.default
    
    func export(notebook: NotebookModel, to destinationURL: URL) async throws {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("Export-\(notebook.id.uuidString)")
        
        try? fileManager.removeItem(at: tempDir)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let sourceDir = tempDir.appendingPathComponent("sources")
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        for source in notebook.sources ?? [] {
            if let localPath = source.localFilePath,
               fileManager.fileExists(atPath: localPath) {
                let fileExtension = (localPath as NSString).pathExtension
                let dest = sourceDir.appendingPathComponent("\(source.id.uuidString).\(fileExtension)")
                try? fileManager.copyItem(atPath: localPath, toPath: dest.path)
            }
        }
        
        let exportData = buildManifest(notebook: notebook)
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        jsonEncoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try jsonEncoder.encode(exportData)
        let manifestURL = tempDir.appendingPathComponent("notebook.json")
        try jsonData.write(to: manifestURL)
        
        // Create the zip by archiving the directory contents.
        try ArchiveUtility.createZipArchive(
            fromDirectory: tempDir,
            to: destinationURL,
            fileManager: fileManager
        )
        
        try? fileManager.removeItem(at: tempDir)
    }
    
    func importNotebook(from sourceURL: URL, into context: ModelContext) async throws -> NotebookModel {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("Import-\(UUID().uuidString)")
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer { try? fileManager.removeItem(at: tempDir) }
        
        try ArchiveUtility.extractZipArchive(
            at: sourceURL,
            to: tempDir,
            fileManager: fileManager
        )
        
        let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let manifestDir = contents.first(where: { $0.lastPathComponent.hasPrefix("Export-") }) ?? tempDir else {
            throw ImportExportError.importFailed("Notebook archive is malformed.")
        }
        
        return try importFromDirectory(manifestDir, into: context)
    }
    
    private func importFromDirectory(_ directory: URL, into context: ModelContext) throws -> NotebookModel {
        let manifestURL = directory.appendingPathComponent("notebook.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ImportExportError.importFailed("Notebook archive is missing notebook.json.")
        }
        
        let jsonData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ExportManifest.self, from: jsonData)
        
        let notebook = NotebookModel(title: manifest.notebook.title, subtitle: manifest.notebook.subtitle)
        notebook.createdAt = manifest.notebook.createdAt
        
        context.insert(notebook)
        
        let sourceDir = directory.appendingPathComponent("sources")
        for sourceData in manifest.sources {
            let source = SourceModel(title: sourceData.title, type: SourceType(rawValue: sourceData.type) ?? .text)
            source.id = sourceData.id
            source.url = sourceData.url
            source.extractedText = sourceData.extractedText
            source.addedAt = sourceData.addedAt
            source.metadata = sourceData.metadata
            source.wordCount = sourceData.wordCount
            source.tags = sourceData.tags
            source.status = .ready
            
            if let fileName = sourceData.localFileName {
                let fileURL = sourceDir.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    let storageDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("SourceDesk").appendingPathComponent("sources")
                    try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
                    let destURL = storageDir.appendingPathComponent(UUID().uuidString + "." + (fileName as NSString).pathExtension)
                    try? fileManager.copyItem(at: fileURL, to: destURL)
                    source.localFilePath = destURL.path
                }
            }
            
            source.notebook = notebook
            context.insert(source)
        }
        
        for sessionData in manifest.chatSessions {
            let session = ChatSessionModel(title: sessionData.title)
            session.id = sessionData.id
            session.createdAt = sessionData.createdAt
            session.modifiedAt = sessionData.modifiedAt
            session.notebook = notebook
            context.insert(session)
            
            for messageData in sessionData.messages {
                let message = ChatMessageModel(
                    role: MessageRole(rawValue: messageData.role) ?? .user,
                    content: messageData.content
                )
                message.id = messageData.id
                message.createdAt = messageData.createdAt
                message.model = messageData.model
                message.provider = messageData.provider
                message.citationsJSON = messageData.citationsJSON
                message.session = session
                context.insert(message)
            }
        }
        
        for noteData in manifest.notes {
            let note = NotebookNoteModel(
                title: noteData.title,
                content: noteData.content,
                type: noteData.noteType
            )
            note.id = noteData.id
            note.createdAt = noteData.createdAt
            note.modifiedAt = noteData.modifiedAt
            note.isPinned = noteData.isPinned
            note.notebook = notebook
            context.insert(note)
        }
        
        try context.save()
        return notebook
    }
    
    private func buildManifest(notebook: NotebookModel) -> ExportManifest {
        ExportManifest(
            formatVersion: 1,
            exportedAt: Date(),
            notebook: ExportNotebook(
                id: notebook.id,
                title: notebook.title,
                subtitle: notebook.subtitle,
                createdAt: notebook.createdAt,
                modifiedAt: notebook.modifiedAt,
                isFavorite: notebook.isFavorite,
                tags: notebook.tags
            ),
            sources: (notebook.sources ?? []).map { source in
                ExportSource(
                    id: source.id,
                    title: source.title,
                    type: source.sourceType.rawValue,
                    url: source.url,
                    localFileName: source.localFilePath.map { path in
                        let ext = (path as NSString).pathExtension
                        return "\(source.id.uuidString).\(ext)"
                    },
                    extractedText: source.extractedText,
                    addedAt: source.addedAt,
                    wordCount: source.wordCount,
                    tags: source.tags,
                    metadata: source.metadata
                )
            },
            chatSessions: (notebook.chatSessions ?? []).map { session in
                ExportChatSession(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    modifiedAt: session.modifiedAt,
                    messages: (session.messages ?? []).map { message in
                        ExportMessage(
                            id: message.id,
                            role: message.role.rawValue,
                            content: message.content,
                            createdAt: message.createdAt,
                            model: message.model,
                            provider: message.provider,
                            citationsJSON: message.citationsJSON
                        )
                    }
                )
            },
            notes: (notebook.notes ?? []).map { note in
                ExportNote(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    noteType: note.noteType,
                    createdAt: note.createdAt,
                    modifiedAt: note.modifiedAt,
                    isPinned: note.isPinned
                )
            }
        )
    }
}

/// Uses the macOS `ditto` tool (bundled with the OS) for zip create/extract,
/// avoiding third-party dependencies.
enum ArchiveUtility {
    static func createZipArchive(fromDirectory sourceDir: URL, to destinationURL: URL, fileManager: FileManager) throws {
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDir.path, destinationURL.path]
        )
    }
    
    static func extractZipArchive(at sourceURL: URL, to destinationDir: URL, fileManager: FileManager) throws {
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", sourceURL.path, destinationDir.path]
        )
    }
    
    private static func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ImportExportError.exportFailed("Could not run archive tool: \(error.localizedDescription)")
        }
        
        guard process.terminationStatus == 0 else {
            let stderr = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown archive error"
            throw ImportExportError.exportFailed(stderr)
        }
    }
}

struct ExportManifest: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let notebook: ExportNotebook
    let sources: [ExportSource]
    let chatSessions: [ExportChatSession]
    let notes: [ExportNote]
}

struct ExportNotebook: Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let createdAt: Date
    let modifiedAt: Date
    let isFavorite: Bool
    let tags: [String]
}

struct ExportSource: Codable {
    let id: UUID
    let title: String
    let type: String
    let url: String?
    let localFileName: String?
    let extractedText: String?
    let addedAt: Date
    let wordCount: Int
    let tags: [String]
    let metadata: SourceMetadata
}

struct ExportChatSession: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let modifiedAt: Date
    let messages: [ExportMessage]
}

struct ExportMessage: Codable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date
    let model: String?
    let provider: String?
    let citationsJSON: String?
}

struct ExportNote: Codable {
    let id: UUID
    let title: String
    let content: String
    let noteType: String
    let createdAt: Date
    let modifiedAt: Date
    let isPinned: Bool
}