import Foundation

final class BraveSearchProvider: SearchProvider {
    let name = "Brave"
    private let session: URLSession
    private let keychainService = KeychainService()
    
    var apiKey: String? {
        get { keychainService.getPassword(service: "sourcedesk", account: "brave") }
        set {
            if let key = newValue {
                keychainService.setPassword(key, service: "sourcedesk", account: "brave")
            } else {
                keychainService.deletePassword(service: "sourcedesk", account: "brave")
            }
        }
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    func search(query: String, maxResults: Int = 10) async throws -> [SearchResult] {
        guard let key = apiKey, !key.isEmpty else {
            throw SearchError.providerNotConfigured
        }
        
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=\(maxResults)") else {
            throw SearchError.invalidQuery
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.searchUnavailable
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw SearchError.providerNotConfigured
            }
            throw SearchError.searchUnavailable
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(BraveSearchResponse.self, from: data)
        
        return (apiResponse.web?.results ?? []).map { result in
            SearchResult(
                title: result.title,
                url: result.url,
                snippet: result.description,
                source: "Brave",
                publishedDate: result.pageAge
            )
        }
    }
}

// MARK: - Brave Response Models

private struct BraveSearchResponse: Codable {
    let web: BraveWebResults?
}

private struct BraveWebResults: Codable {
    let results: [BraveWebResult]?
}

private struct BraveWebResult: Codable {
    let title: String
    let url: String
    let description: String
    let pageAge: String?
    
    enum CodingKeys: String, CodingKey {
        case title, url, description
        case pageAge = "page_age"
    }
}