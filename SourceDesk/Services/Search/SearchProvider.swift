import Foundation

protocol SearchProvider: AnyObject {
    var name: String { get }
    func search(query: String, maxResults: Int) async throws -> [SearchResult]
}

struct SearchResult: Identifiable, Codable {
    var id: UUID
    var title: String
    var url: String
    var snippet: String
    var source: String
    var publishedDate: String?
    
    init(title: String, url: String, snippet: String, source: String, publishedDate: String? = nil) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.snippet = snippet
        self.source = source
        self.publishedDate = publishedDate
    }
}

enum SearchProviderType: String, CaseIterable, Identifiable {
    case duckduckgo = "duckduckgo"
    case brave = "brave"
    case disabled = "disabled"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .disabled: return "Disabled"
        }
    }
}

final class DuckDuckGoSearchProvider: SearchProvider {
    let name = "DuckDuckGo"
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    func search(query: String, maxResults: Int = 10) async throws -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        
        let urlString = "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidQuery
        }
        
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SearchError.searchUnavailable
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        var results: [SearchResult] = []
        
        if let abstractText = apiResponse.abstractText, !abstractText.isEmpty {
            results.append(SearchResult(
                title: apiResponse.headline ?? "DuckDuckGo Result",
                url: apiResponse.abstractURL ?? apiResponse.entity,
                snippet: abstractText,
                source: "DuckDuckGo"
            ))
        }
        
        for topic in (apiResponse.relatedTopics ?? []) {
            guard results.count < maxResults else { break }
            switch topic {
            case .string(_):
                break
            case .object(let obj):
                if let text = obj.text, !text.isEmpty, let url = obj.firstURL {
                    results.append(SearchResult(
                        title: text.split(separator: " - ").first.map(String.init) ?? "Result",
                        url: url,
                        snippet: text,
                        source: "DuckDuckGo"
                    ))
                }
            }
        }
        
        return results
    }
}

enum SearchError: LocalizedError {
    case invalidQuery
    case searchUnavailable
    case noResults
    case providerNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is invalid."
        case .searchUnavailable:
            return "The search service is unavailable."
        case .noResults:
            return "No search results were found."
        case .providerNotConfigured:
            return "No search provider is configured."
        }
    }
}

// MARK: - DuckDuckGo Response Models

private struct DuckDuckGoResponse: Codable {
    let headline: String?
    let abstractText: String?
    let abstractURL: String?
    let entity: String
    let relatedTopics: [DuckDuckGoTopic]?
    
    enum CodingKeys: String, CodingKey {
        case headline = "Heading"
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case entity = "Entity"
        case relatedTopics = "RelatedTopics"
    }
}

private enum DuckDuckGoTopic: Codable {
    case string(String)
    case object(RelatedTopicObject)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let obj = try? container.decode(RelatedTopicObject.self) {
            self = .object(obj)
        } else {
            self = .string("")
        }
    }
    
    func encode(to encoder: Encoder) throws {}
}

private struct RelatedTopicObject: Codable {
    let text: String?
    let firstURL: String?
    
    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
    }
}