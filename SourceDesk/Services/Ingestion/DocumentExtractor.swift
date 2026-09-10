import Foundation
import PDFKit
import AppKit

enum FileExtractionError: LocalizedError {
    case fileNotFound(String)
    case unreadableFormat(String)
    case emptyFile(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "The file \"\(name)\" could not be found."
        case .unreadableFormat(let name):
            return "The file \"\(name)\" could not be read. It may be corrupted or in an unsupported format."
        case .emptyFile(let name):
            return "The file \"\(name)\" contains no text."
        }
    }
}

actor DocumentExtractor {
    func extractPDF(from url: URL) throws -> ExtractedDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileExtractionError.fileNotFound(url.lastPathComponent)
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw FileExtractionError.unreadableFormat(url.lastPathComponent)
        }
        
        var pages: [ExtractedPage] = []
        var totalText = ""
        
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            guard let pageText = page.string else { continue }
            
            let cleaned = TextCleaner.clean(pageText)
            if !cleaned.isEmpty {
                pages.append(ExtractedPage(
                    text: cleaned,
                    pageNumber: pageIndex + 1
                ))
                totalText += cleaned + "\n\n"
            }
        }
        
        guard !totalText.isEmpty else {
            throw FileExtractionError.emptyFile(url.lastPathComponent)
        }
        
        let title = pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? url.deletingPathExtension().lastPathComponent
        let author = pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        let pageCount = pdfDocument.pageCount
        
        return ExtractedDocument(
            title: title,
            text: TextCleaner.clean(totalText),
            pages: pages,
            author: author,
            pageCount: pageCount
        )
    }
    
    func extractTextFile(from url: URL) async throws -> ExtractedDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileExtractionError.fileNotFound(url.lastPathComponent)
        }
        
        var text: String?
        
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt", "text", "md", "markdown", "xml", "csv", "json", "yaml", "yml":
            text = try? String(contentsOf: url, encoding: .utf8)
            if text == nil {
                text = try? String(contentsOf: url, encoding: .isoLatin1)
            }
        case "rtf":
            if let attributed = try? NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                text = attributed.string
            }
        case "docx":
            text = extractDOCX(from: url)
        case "html", "htm":
            if let htmlString = try? String(contentsOf: url, encoding: .utf8) {
                text = await extractHTMLContent(htmlString)
            }
        default:
            text = nil
        }
        
        guard let finalText = text, !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileExtractionError.emptyFile(url.lastPathComponent)
        }
        
        let cleaned = TextCleaner.clean(finalText)
        let title = url.deletingPathExtension().lastPathComponent
        
        return ExtractedDocument(
            title: title,
            text: cleaned,
            pages: [ExtractedPage(text: cleaned, pageNumber: nil)],
            pageCount: nil
        )
    }
    
    func extractHTMLContent(_ html: String) async -> String {
        let extractor = ContentExtractor()
        return await extractor.extractMainContent(from: html)
    }
    
    func extractFromString(_ string: String, title: String) -> ExtractedDocument {
        let cleaned = TextCleaner.clean(string)
        return ExtractedDocument(
            title: title,
            text: cleaned,
            pages: [ExtractedPage(text: cleaned, pageNumber: nil)],
            pageCount: nil
        )
    }
    
    private func extractDOCX(from url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url)
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("zip")
            
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            let extractDir = tempURL.deletingPathExtension()
            try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: extractDir) }
            
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", tempURL.path, "-d", extractDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #endif
            
            let documentXML = extractDir.appendingPathComponent("word/document.xml")
            guard let xmlString = try? String(contentsOf: documentXML, encoding: .utf8) else {
                return nil
            }
            
            let cleanedXML = xmlString
                .replacingOccurrences(of: "</w:p>", with: "\n")
                .replacingOccurrences(of: "</w:tab>", with: "\t")
            
            return cleanXML(xml: cleanedXML)
        } catch {
            return nil
        }
    }
    
    private func cleanXML(xml: String) -> String {
        let regex = try! NSRegularExpression(pattern: "<[^>]+>")
        let range = NSRange(xml.startIndex..., in: xml)
        let cleaned = regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "")
        
        return cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

struct ExtractedPage {
    let text: String
    let pageNumber: Int?
}

struct ExtractedDocument {
    let title: String
    let text: String
    let pages: [ExtractedPage]
    let author: String?
    let pageCount: Int?
    
    init(title: String, text: String, pages: [ExtractedPage], author: String? = nil, pageCount: Int? = nil) {
        self.title = title
        self.text = text
        self.pages = pages
        self.author = author
        self.pageCount = pageCount
    }
}