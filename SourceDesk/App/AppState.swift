import SwiftUI
import Combine
import Network

@MainActor
class AppState: ObservableObject {
    @Published var selectedNotebookID: UUID?
    @Published var selectedSourceID: UUID?
    @Published var selectedTab: SidebarTab = .notebooks
    @Published var centerTab = "sources"
    @Published var rightPanelTab: RightPanelTab = .source
    @Published var selectedRightPanelCitation: Citation?
    @Published var isOnline: Bool = true
    @Published var activeProviders: [AIProviderConfig] = []
    @Published var searchMode: SearchMode = .notebookOnly
    
    let aiManager = AIManager()
    let searchManager = SearchManager()
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sourcedesk.networkmonitor")
    
    enum SidebarTab: String, CaseIterable {
        case notebooks = "Notebooks"
        case favorites = "Favorites"
        case recent = "Recent"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .notebooks: return "book"
            case .favorites: return "star"
            case .recent: return "clock"
            case .settings: return "gearshape"
            }
        }
    }
    
    enum RightPanelTab: String, CaseIterable {
        case source = "Source"
        case citations = "Citations"
        case search = "Search"
        case notes = "Notes"
        
        var icon: String {
            switch self {
            case .source: return "doc.text"
            case .citations: return "text.quote"
            case .search: return "magnifyingglass"
            case .notes: return "note.text"
            }
        }
    }
    
    enum SearchMode: String, CaseIterable {
        case notebookOnly = "Notebook Only"
        case notebookAndWeb = "Notebook + Web"
        case webOnly = "Web Only"
    }
    
    init() {
        startNetworkMonitoring()
        loadProviderConfigs()
    }
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func loadProviderConfigs() {
        let saved = UserDefaults.standard.array(forKey: "activeProviders") as? [String] ?? ["ollama"]
        activeProviders = saved.compactMap { AIProviderConfig(rawValue: $0) }
    }
    
    func saveProviderConfigs() {
        UserDefaults.standard.set(activeProviders.map(\.rawValue), forKey: "activeProviders")
    }
}

enum AIProviderConfig: String, CaseIterable, Identifiable {
    case ollama = "ollama"
    case openai = "openai"
    case anthropic = "anthropic"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        }
    }
    
    var icon: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .openai: return "brain.head.profile"
        case .anthropic: return "cloud"
        }
    }
    
    var isLocal: Bool {
        switch self {
        case .ollama: return true
        default: return false
        }
    }
}
