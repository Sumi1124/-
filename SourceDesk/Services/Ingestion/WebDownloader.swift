import Foundation
import AppKit

struct WebPageContent {
    let html: String
    let title: String?
    let finalURL: URL
    let headers: [String: String]
    let mimeType: String?
}

enum WebFetchError: LocalizedError {
    case invalidURL(String)
    case unsupportedScheme(String)
    case networkError(String)
    case timeout
    case tooLarge(Int64)
    case httpError(Int)
    case accessDenied
    case robotsBlocked
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let s):
            return "The URL \"\(s)\" is not valid."
        case .unsupportedScheme(let s):
            return "Unsupported URL scheme: \(s). Only http and https are supported."
        case .networkError(let s):
            return "Network error while downloading: \(s)"
        case .timeout:
            return "The download timed out. The website did not respond in time."
        case .tooLarge(let size):
            let mb = Double(size) / 1024 / 1024
            return String(format: "The web page is too large (%.1f MB).", mb)
        case .httpError(let code):
            return "The website returned an HTTP error: \(code)."
        case .accessDenied:
            return "Access to this website was denied. It may require authentication or block automated access."
        case .robotsBlocked:
            return "This website's robots.txt disallows automated access."
        }
    }
}

actor WebDownloader {
    private let session: URLSession
    private let maxDownloadSize: Int64 = 60 * 1024 * 1024
    private let timeoutInterval: TimeInterval = 60
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    func download(urlString: String) async throws -> WebPageContent {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw WebFetchError.invalidURL(urlString)
        }
        
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw WebFetchError.unsupportedScheme(url.scheme ?? "unknown")
        }
        
        try await checkRobots(for: url)
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.cachePolicy = .useProtocolCachePolicy
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebFetchError.networkError("Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw WebFetchError.accessDenied
        case 404:
            throw WebFetchError.httpError(404)
        case 429:
            throw WebFetchError.httpError(429)
        default:
            throw WebFetchError.httpError(httpResponse.statusCode)
        }
        
        var data = Data()
        var totalBytes: Int64 = 0
        
        let contentLength = httpResponse.expectedContentLength
        if contentLength > maxDownloadSize, contentLength > 0 {
            throw WebFetchError.tooLarge(contentLength)
        }
        
        for try await byte in bytes {
            try Task.checkCancellation()
            totalBytes += 1
            if totalBytes > maxDownloadSize {
                throw WebFetchError.tooLarge(totalBytes)
            }
            data.append(byte)
        }
        
        let mimeType = httpResponse.mimeType
        let finalURL = httpResponse.url ?? url
        
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw WebFetchError.networkError("Could not decode page content")
        }
        
        var headers: [String: String] = [:]
        httpResponse.allHeaderFields.forEach { key, value in
            headers[String(describing: key)] = String(describing: value)
        }
        
        return WebPageContent(
            html: html,
            title: nil,
            finalURL: finalURL,
            headers: headers,
            mimeType: mimeType
        )
    }
    
    func downloadBinary(url: URL, maxSize: Int64) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebFetchError.networkError("Invalid response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw WebFetchError.httpError(httpResponse.statusCode)
        }
        
        var data = Data()
        var totalBytes: Int64 = 0
        
        for try await byte in bytes {
            totalBytes += 1
            if totalBytes > maxSize {
                throw WebFetchError.tooLarge(totalBytes)
            }
            data.append(byte)
        }
        
        return data
    }
    
    private func checkRobots(for url: URL) async throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        guard let host = url.host else { return }
        
        let robotsURL = URL(string: "\(scheme)://\(host)/robots.txt")
        guard let robotsURL else { return }
        
        do {
            let (data, response) = try await session.data(from: robotsURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            
            guard let robotsText = String(data: data, encoding: .utf8) else { return }
            
            let parser = RobotsTxtParser(robotsText: robotsText)
            if parser.isDisallowed(url: url) {
                throw WebFetchError.robotsBlocked
            }
        } catch {
            if case WebFetchError.robotsBlocked = error {
                throw error
            }
            return
        }
    }
}

struct RobotsTxtParser {
    private let disallowedPaths: [String]
    
    init(robotsText: String) {
        var paths: [String] = []
        var currentUserAgentMatched = false
        
        for line in robotsText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            
            let field = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            
            switch field {
            case "user-agent":
                currentUserAgentMatched = value.lowercased() == "*"
            case "disallow":
                if currentUserAgentMatched && !value.isEmpty {
                    paths.append(value)
                }
            default:
                break
            }
        }
        
        self.disallowedPaths = paths
    }
    
    func isDisallowed(url: URL) -> Bool {
        let path = url.path.isEmpty ? "/" : url.path
        for disallowed in disallowedPaths {
            if path.hasPrefix(disallowed) {
                return true
            }
        }
        return false
    }
}

actor ContentExtractor {
    func extractTitle(from html: String) -> String? {
        if let range = html.range(of: "<title[^>]*>", options: .regularExpression) {
            let afterOpen = html[range.upperBound...]
            if let closeRange = afterOpen.range(of: "</title>") {
                let title = String(afterOpen[..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }
    
    func extractMetaDescription(from html: String) -> String? {
        let pattern = "<meta[^>]*name=[\"']description[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let contentRange = Range(match.range(at: 1), in: html) {
            return String(html[contentRange])
        }
        
        let altPattern = "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*name=[\"']description[\"'][^>]*>"
        if let regex = try? NSRegularExpression(pattern: altPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let contentRange = Range(match.range(at: 1), in: html) {
            return String(html[contentRange])
        }
        
        return nil
    }
    
    func extractMainContent(from html: String) -> String {
        let cleanedHTML = removeScriptsAndStyles(html)
        let articleContent = extractArticle(cleanedHTML)
        return TextCleaner.clean(articleContent)
    }
    
    private func removeScriptsAndStyles(_ html: String) -> String {
        var cleaned = html
        
        if let regex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        
        if let regex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        
        if let regex = try? NSRegularExpression(pattern: "<(script|style|noscript|nav|header|footer|aside)[^>]*>.*?</\\1>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        
        return cleaned
    }
    
    private func extractArticle(_ html: String) -> String {
        let cleaned = html
            .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</blockquote>", with: "\n\n", options: .caseInsensitive)
        
        let strippedTags = removeHTMLTags(cleaned)
        let decoded = decodeHTMLEntities(strippedTags)
        return TextCleaner.removeNavigationItems(decoded)
    }
    
    private func removeHTMLTags(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        return result
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        guard let attributed = try? NSAttributedString(
            data: Data(text.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else {
            return text
        }
        return attributed.string
    }
}