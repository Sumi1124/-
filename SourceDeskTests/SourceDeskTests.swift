import XCTest

final class TextProcessingTests: XCTestCase {
    func testTokenEstimatorCountsWords() {
        let text = "The quick brown fox jumps over the lazy dog"
        XCTAssertGreaterThan(TokenEstimator.count(text), 0)
        XCTAssertLessThan(TokenEstimator.count(text), 20)
    }
    
    func testTruncateKeepsShortText() {
        let text = "Short text"
        XCTAssertEqual(TokenEstimator.truncate(text, toTokenLimit: 100), text)
    }
    
    func testTruncateShortensLongText() {
        let longText = String(repeating: "word ", count: 500)
        let truncated = TokenEstimator.truncate(longText, toTokenLimit: 50)
        XCTAssertLessThan(TokenEstimator.count(truncated), TokenEstimator.count(longText))
        XCTAssertLessThan(truncated.count, longText.count)
    }
    
    func testCleanerCollapsesWhitespace() {
        let dirty = "Hello   world\r\n\n\n\nsecond   line"
        let clean = TextCleaner.clean(dirty)
        XCTAssertTrue(clean.contains("Hello world"))
        XCTAssertTrue(clean.contains("second line"))
    }
    
    func testRemovalOfNavigationItems() {
        let text = "Main content. menu \n \nnext section"
        let cleaned = TextCleaner.removeNavigationItems(text)
        XCTAssertFalse(cleaned.lowercased().contains("menu"))
    }
    
    func testSplitIntoSentences() {
        let text = "The first sentence. The second sentence! And the third?"
        let sentences = TextChunker.splitIntoSentences(text)
        XCTAssertGreaterThanOrEqual(sentences.count, 2)
        XCTAssertTrue(sentences[0].contains("first"))
    }
}

final class ChunkingTests: XCTestCase {
    func testShortTextReturnsSingleChunk() {
        let text = "A short paragraph that fits easily in one chunk."
        let chunks = try! TextChunker.chunk(text: text, maxTokens: 100)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, text)
    }
    
    func testLongTextProducesMultipleChunks() {
        var paragraphs = ""
        for i in 0..<30 {
            paragraphs += "This is paragraph number \(i) with enough content to be meaningful for testing purposes and to generate a reasonable amount of text overall. It repeats concepts about source materials and research annotations. "
        }
        let chunks = try! TextChunker.chunk(text: paragraphs, maxTokens: 150, overlapTokens: 20)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertFalse(chunk.content.isEmpty)
        }
    }
    
    func testEmptyTextThrows() {
        XCTAssertThrowsError(try TextChunker.chunk(text: "   \n  ", maxTokens: 100))
    }
    
    func testChunkOffsetsAreMonotonic() {
        var paragraphs = ""
        for i in 0..<20 {
            paragraphs += "Paragraph \(i) with enough content for testing the chunker's offset tracking behavior across multiple segments. "
        }
        let chunks = try! TextChunker.chunk(text: paragraphs, maxTokens: 200, overlapTokens: 30)
        for i in 1..<chunks.count {
            XCTAssertGreaterThan(chunks[i].startOffset, chunks[i-1].startOffset)
        }
    }
}

final class CitationParsingTests: XCTestCase {
    func testCitationParseExtractsIndices() {
        let chatVM = CitationParser()
        let citations = chatVM.parse("The Industrial Revolution caused changes. [Source 3] More text here [Source 1]")
        XCTAssertEqual(citations.count, 2)
        XCTAssertEqual(citations[0], 3)
        XCTAssertEqual(citations[1], 1)
    }
    
    func testCitationParseNoCitations() {
        let chatVM = CitationParser()
        let citations = chatVM.parse("No citations here at all.")
        XCTAssertTrue(citations.isEmpty)
    }
}

final class CitationParser {
    func parse(_ text: String) -> [Int] {
        let pattern = #"\[Source (\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        
        var indices: [Int] = []
        var seen = Set<Int>()
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text),
                  let index = Int(text[range]) else { continue }
            if seen.insert(index).inserted {
                indices.append(index)
            }
        }
        return indices
    }
}