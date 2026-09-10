import Foundation

enum TokenEstimator {
    static func count(_ text: String) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return 0 }
        let wordCount = words.count * 4 / 3
        return max(wordCount, 1)
    }
    
    static func truncate(_ text: String, toTokenLimit limit: Int) -> String {
        let current = count(text)
        if current <= limit { return text }
        
        let charLimit = max(text.count * limit / current, 100)
        let truncated = String(text.prefix(charLimit))
        return truncated + "\n\n[Truncated...]"
    }
}

enum TextChunker {
    enum ChunkingError: LocalizedError {
        case emptyText
        
        var errorDescription: String? {
            switch self {
            case .emptyText: return "The text is empty and cannot be chunked."
            }
        }
    }
    
    static func chunk(
        text: String,
        maxTokens: Int = 800,
        overlapTokens: Int = 100
    ) throws -> [TextChunk] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChunkingError.emptyText
        }
        
        if TokenEstimator.count(text) <= maxTokens {
            return [TextChunk(content: text, index: 0, startOffset: 0, endOffset: text.count)]
        }
        
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Split paragraphs that are individually larger than maxTokens so that
        // single-paragraph documents (common with PDF extraction) still chunk.
        var units: [String] = []
        for paragraph in paragraphs {
            if TokenEstimator.count(paragraph) > maxTokens {
                let sentenceChunks = chunkByTokenBound(text: paragraph, maxTokens: maxTokens)
                units.append(contentsOf: sentenceChunks)
            } else {
                units.append(paragraph)
            }
        }
        
        var chunks: [TextChunk] = []
        var currentText = ""
        var startOffset = 0
        var chunkIndex = 0
        
        for paragraph in units {
            if !currentText.isEmpty && TokenEstimator.count(currentText + "\n\n" + paragraph) > maxTokens {
                let endOffset = startOffset + currentText.count
                if TokenEstimator.count(currentText) > 10 {
                    chunks.append(TextChunk(content: currentText, index: chunkIndex, startOffset: startOffset, endOffset: endOffset))
                    chunkIndex += 1
                }
                
                if overlapTokens > 0 && !currentText.isEmpty {
                    let overlapChars = max(currentText.count * overlapTokens / maxTokens, 50)
                    let overlapStart = max(0, currentText.count - overlapChars)
                    let overlapText = String(currentText.suffix(from: currentText.index(currentText.startIndex, offsetBy: overlapStart)))
                    startOffset += currentText.count - overlapText.count
                    currentText = overlapText
                } else {
                    currentText = ""
                    startOffset = endOffset
                }
            }
            
            currentText += (currentText.isEmpty ? "" : "\n\n") + paragraph
        }
        
        if TokenEstimator.count(currentText) > 10 {
            chunks.append(TextChunk(content: currentText, index: chunkIndex, startOffset: startOffset, endOffset: startOffset + currentText.count))
        }
        
        return chunks
    }
    
    private static func chunkByTokenBound(text: String, maxTokens: Int) -> [String] {
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else {
            let charLimit = max(maxTokens * 4, 100)
            return stride(from: 0, to: text.count, by: charLimit).map { start in
                let end = min(start + charLimit, text.count)
                let startIndex = text.index(text.startIndex, offsetBy: start)
                let endIndex = text.index(text.startIndex, offsetBy: end)
                return String(text[startIndex..<endIndex])
            }
        }
        
        var result: [String] = []
        var current = ""
        for sentence in sentences {
            if !current.isEmpty && TokenEstimator.count(current + " " + sentence) > maxTokens {
                if !current.isEmpty {
                    result.append(current)
                }
                current = sentence
                while TokenEstimator.count(current) > maxTokens {
                    let charLimit = max(maxTokens * 4, 100)
                    let truncated = String(current.prefix(charLimit))
                    result.append(truncated)
                    current = String(current.dropFirst(charLimit))
                }
            } else {
                current += (current.isEmpty ? "" : " ") + sentence
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
    
    static func chunkBySentences(
        text: String,
        maxSentences: Int = 5
    ) -> [TextChunk] {
        let sentences = splitIntoSentences(text)
        var chunks: [TextChunk] = []
        var offset = 0
        
        for i in stride(from: 0, to: sentences.count, by: maxSentences) {
            let end = min(i + maxSentences, sentences.count)
            let group = sentences[i..<end]
            let content = group.joined(separator: " ")
            chunks.append(TextChunk(content: content, index: i / maxSentences, startOffset: offset, endOffset: offset + content.count))
            offset += content.count + 1
        }
        
        return chunks
    }
    
    static func splitIntoSentences(_ text: String) -> [String] {
        let pattern = "(?<=[.?!])\\s+(?=[A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        
        var sentences: [String] = []
        if let regex {
            let matches = regex.matches(in: text, range: range)
            var lastMatchEnd = text.startIndex
            
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                sentences.append(String(text[lastMatchEnd..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
                lastMatchEnd = range.upperBound
            }
            
            if lastMatchEnd < text.endIndex {
                sentences.append(String(text[lastMatchEnd...]).trimmingCharacters(in: .whitespaces))
            }
        } else {
            sentences = text.components(separatedBy: ". ")
        }
        
        return sentences.filter { !$0.isEmpty }
    }
}

struct TextChunk {
    let content: String
    let index: Int
    let startOffset: Int
    let endOffset: Int
    let pageNumber: Int?
    
    init(content: String, index: Int, startOffset: Int, endOffset: Int, pageNumber: Int? = nil) {
        self.content = content
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.pageNumber = pageNumber
    }
}

enum TextCleaner {
    static func clean(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "\u{00A0}", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        cleaned = collapseMultipleNewlines(cleaned)
        cleaned = collapseMultipleSpaces(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func collapseMultipleNewlines(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\n{3,}")
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n\n")
    }
    
    static func collapseMultipleSpaces(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: " {2,}")
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }
    
    static func removeNavigationItems(_ text: String) -> String {
        var cleaned = text
        let navigationPatterns = [
            "(?i)^\\s*(menu|navigation|home|back to top|next|previous)\\s*$",
            "(?i)\\b(cookie policy|accept cookies|privacy policy)\\b",
            "(?i)\\b(sign up|sign in|subscribe to our newsletter)\\b"
        ]
        
        for pattern in navigationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        
        return cleaned
    }
}