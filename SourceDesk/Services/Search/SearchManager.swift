import Foundation

@MainActor
class SearchManager: ObservableObject {
    @Published var searchProviderType: SearchProviderType {
        didSet {
            UserDefaults.standard.set(searchProviderType.rawValue, forKey: "searchProvider")
        }
    }
    
    private let duckduckgo = DuckDuckGoSearchProvider()
    private let brave = BraveSearchProvider()
    
    init() {
        let saved = UserDefaults.standard.string(forKey: "searchProvider") ?? "duckduckgo"
        self.searchProviderType = SearchProviderType(rawValue: saved) ?? .duckduckgo
    }
    
    var currentProvider: SearchProvider? {
        switch searchProviderType {
        case .duckduckgo:
            return duckduckgo
        case .brave:
            return brave
        case .disabled:
            return nil
        }
    }
    
    var braveAPIKeyConfigured: Bool {
        !(brave.apiKey?.isEmpty ?? true)
    }
    
    var currentBraveKey: String {
        brave.apiKey ?? ""
    }
    
    func setBraveAPIKey(_ key: String) {
        brave.apiKey = key
    }
    
    func search(query: String, maxResults: Int = 10) async throws -> [SearchResult] {
        guard let provider = currentProvider else {
            throw SearchError.providerNotConfigured
        }
        return try await provider.search(query: query, maxResults: maxResults)
    }
}