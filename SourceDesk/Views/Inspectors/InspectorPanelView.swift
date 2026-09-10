import SwiftUI
import SwiftData

struct InspectorPanelView: View {
    @ObservedObject var sourceVM: SourceViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var aiManager: AIManager
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $appState.rightPanelTab) {
                ForEach(AppState.RightPanelTab.allCases, id: \.self) { tab in
                    Image(systemName: tab.icon).tag(tab)
                        .help(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            Group {
                switch appState.rightPanelTab {
                case .source:
                    SourceInspectorView(sourceVM: sourceVM, appState: appState)
                case .citations:
                    CitationInspectorView(selectedCitation: $appState.selectedRightPanelCitation)
                case .search:
                    SearchInspectorView()
                case .notes:
                    NotebookSummaryView()
                }
            }
        }
    }
}

// MARK: - Source Inspector

struct SourceInspectorView: View {
    @ObservedObject var sourceVM: SourceViewModel
    @ObservedObject var appState: AppState
    
    private var selectedSource: SourceModel? {
        guard let id = appState.selectedSourceID else { return nil }
        return sourceVM.sources.first { $0.id == id }
    }
    
    var body: some View {
        Group {
            if let source = selectedSource {
                sourceDetail(source)
            } else if let first = sourceVM.sources.first {
                sourceDetail(first)
            } else {
                EmptyInspectorView(icon: "doc.badge.plus", title: "No Source Selected", message: "Select a source to view its contents and citation details here.")
            }
        }
    }
    
    private func sourceDetail(_ source: SourceModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: source.sourceType.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(source.sourceType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if source.status == .error {
                        errorBanner(source)
                    }
                    
                    metadataGrid(source)
                    
                    Divider()
                    
                    if let text = source.extractedText, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("No extracted content", systemImage: "doc.questionmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
    }
    
    private func metadataGrid(_ source: SourceModel) -> some View {
        let rows: [(String, String?)] = [
            ("URL", source.url),
            ("Added", source.addedAt.formatted(date: .abbreviated, time: .shortened)),
            ("Words", source.wordCount == 0 ? nil : "\(source.wordCount)"),
            ("Chunks", source.chunkCount == 0 ? nil : "\(source.chunkCount)"),
            ("Pages", source.metadata.pageCount.map(String.init)),
            ("Author", source.metadata.author),
            ("Site", source.metadata.siteName)
        ]
        
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.filter { $0.1 != nil }, id: \.0) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text(row.1!)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                }
            }
        }
    }
    
    private func errorBanner(_ source: SourceModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Processing failed")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(source.errorMessage ?? "Unknown error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    sourceVM.reprocessSource(source)
                }
                .font(.caption)
                .controlSize(.small)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Citation Inspector

struct CitationInspectorView: View {
    @Binding var selectedCitation: Citation?
    
    var body: some View {
        Group {
            if let citation = selectedCitation {
                citationDetail(citation)
            } else {
                EmptyInspectorView(icon: "text.quote", title: "No Citation Selected", message: "Citations appear in Research answers. Click a citation to inspect its source text.")
            }
        }
    }
    
    private func citationDetail(_ citation: Citation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("[Source \(citation.citationIndex)]")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    Text(citation.sourceTitle)
                        .font(.headline)
                    Spacer()
                }
                
                metadataGrid(citation)
                
                Divider()
                
                Text("Excerpt")
                    .font(.headline)
                Text(citation.excerpt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding()
        }
    }
    
    private func metadataGrid(_ citation: Citation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = citation.url {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    if let url = URL(string: url) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }
            }
            if let page = citation.pageNumber {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Page \(page)")
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Search Inspector

struct SearchInspectorView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notebook & web…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding()
            
            Divider()
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                Spacer()
            } else if results.isEmpty {
                EmptyInspectorView(icon: "magnifyingglass", title: "Search", message: "Search across your notebook's sources and the web. Web search must be enabled in Settings.")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(results) { result in
                            SearchResultRow(result: result)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        
        let web = try? await appState.searchManager.search(query: query, maxResults: 8)
        results = web ?? []
        
        isSearching = false
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(result.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    if let url = URL(string: result.url) {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
            }
            Text(result.snippet)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Notebook Summary

struct NotebookSummaryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notebook Overview")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book")
                        .foregroundStyle(.secondary)
                    Text("Notebook")
                    Spacer()
                    Text("Selected")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("Sources")
                    Spacer()
                    Text("—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(.secondary)
                    Text("Chats")
                    Spacer()
                    Text("—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                    Text("Notes")
                    Spacer()
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            
            Text("Storage")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text("Local-first")
                    Spacer()
                    Text("No cloud upload")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text("Storage")
                    Spacer()
                    Text(freeDiskSpace)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            
            Text("Privacy")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Label("Sources remain on your Mac.", systemImage: "lock.fill")
                    .font(.caption)
                Label("Answers go to the selected AI provider.", systemImage: "arrow.up.circle")
                    .font(.caption)
                Label("Web search sends queries to the search provider.", systemImage: "globe")
                    .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var freeDiskSpace: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return "unknown"
        }
        return ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }
}

// MARK: - Empty State

struct EmptyInspectorView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}