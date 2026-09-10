import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        TabView {
            ProviderSettingsView(aiManager: appState.aiManager)
                .tabItem { Label("AI Providers", systemImage: "cpu") }
            
            SearchSettingsView(searchManager: appState.searchManager)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            
            AppAdvancedSettingsView(aiManager: appState.aiManager)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - AI Providers

struct ProviderSettingsView: View {
    @ObservedObject var aiManager: AIManager
    @EnvironmentObject private var appState: AppState
    
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    
    private var selectedOllamaModel: Binding<AIModel?> {
        Binding(
            get: { aiManager.ollama.selectedModel },
            set: { newValue in
                if let model = newValue { aiManager.selectModel(model) }
            }
        )
    }
    
    private var selectedOpenAIModel: Binding<AIModel?> {
        Binding(
            get: { aiManager.openai.selectedModel },
            set: { newValue in
                if let model = newValue { aiManager.selectModel(model) }
            }
        )
    }
    
    private var selectedAnthropicModel: Binding<AIModel?> {
        Binding(
            get: { aiManager.anthropic.selectedModel },
            set: { newValue in
                if let model = newValue { aiManager.selectModel(model) }
            }
        )
    }
    
    var body: some View {
        Form {
            Section("Local Models") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ollama")
                            .font(.headline)
                        Text("Runs models locally on your Mac. Source content never leaves your machine when using local models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: aiManager.ollamaIsAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(aiManager.ollamaIsAvailable ? Color.green : Color.red)
                        Text(aiManager.ollamaDiagnostic.statusMessage)
                            .font(.callout)
                            .lineLimit(2)
                        Button("Refresh") { aiManager.refreshOllamaStatus() }
                            .controlSize(.small)
                    }
                }
                
                Picker("Selected Model", selection: selectedOllamaModel) {
                    Text("None").tag(AIModel?.none)
                    ForEach(aiManager.availableModelList, id: \.id) { model in
                        Text(model.name).tag(AIModel?.some(model))
                    }
                }
                
                if aiManager.ollamaIsAvailable && aiManager.availableModelList.isEmpty {
                    Text("Ollama is running but no models are installed locally. Install one manually:  ollama pull llama3.1")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Section("OpenAI") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenAI")
                            .font(.headline)
                        Text("ChatGPT-compatible API. Requires an OpenAI API key. Queries are sent to OpenAI servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                SecureField("API Key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { openAIKey = aiManager.openai.apiKey ?? "" }
                    .onChange(of: openAIKey) { _, newValue in
                        aiManager.openai.apiKey = newValue.isEmpty ? nil : newValue
                    }
                
                Picker("Selected Model", selection: selectedOpenAIModel) {
                    Text("None").tag(AIModel?.none)
                    ForEach(AIManager.openAIModels, id: \.id) { model in
                        Text(model.name).tag(AIModel?.some(model))
                    }
                }
            }
            
            Section("Anthropic Claude") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cloud")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Anthropic Claude")
                            .font(.headline)
                        Text("Requires an Anthropic API key. Queries are sent to Anthropic servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                SecureField("API Key", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { anthropicKey = aiManager.anthropic.apiKey ?? "" }
                    .onChange(of: anthropicKey) { _, newValue in
                        aiManager.anthropic.apiKey = newValue.isEmpty ? nil : newValue
                    }
                
                Picker("Selected Model", selection: selectedAnthropicModel) {
                    Text("None").tag(AIModel?.none)
                    ForEach(AIManager.anthropicModels, id: \.id) { model in
                        Text(model.name).tag(AIModel?.some(model))
                    }
                }
            }
            
            Section {
                Text("API keys are stored in your Mac's Keychain. Source content is never uploaded unless you explicitly use a cloud AI provider, in which case the context you send to it may include relevant excerpts from your sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Providers")
    }
}

// MARK: - Search

struct SearchSettingsView: View {
    @ObservedObject var searchManager: SearchManager
    @State private var braveKey = ""
    
    var body: some View {
        Form {
            Section("Web Search Provider") {
                Picker("Enabled Provider", selection: $searchManager.searchProviderType) {
                    ForEach(SearchProviderType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }
            
            Section("DuckDuckGo") {
                HStack {
                    Image(systemName: "duck")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text("Free and no API key required")
                            .font(.callout)
                        Text("Provides instant answers and related topics. Coverage can be limited for niche queries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Brave Search") {
                SecureField("API Key", text: $braveKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { braveKey = searchManager.currentBraveKey }
                    .onChange(of: braveKey) { _, newValue in
                        searchManager.setBraveAPIKey(newValue.isEmpty ? "" : newValue)
                    }
                Text("Brave Search API provides full web search results. Get a key at search.brave.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("How Web Search Works") {
                Text("When you enable web search, your query is sent to the selected search provider. Web results are kept separate from your notebook sources and cited as web results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Search")
    }
}

// MARK: - Storage

struct StorageSettingsView: View {
    @State private var storageInfo: (path: String, size: String) = ("", "Calculating…")
    
    var body: some View {
        Form {
            Section("Storage Location") {
                LabeledContent("Notebook data") {
                    Text(pathLabel)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                LabeledContent("Used space") {
                    Text(storageInfo.size)
                        .font(.callout)
                }
                LabeledContent("Free disk space") {
                    Text(freeDiskSpace)
                        .font(.callout)
                }
                Button("Reveal in Finder") { revealInFinder() }
            }
            
            Section("Cache") {
                Button("Open Cache Folder") { openCacheFolder() }
            }
            
            Section("Import / Export") {
                Text("Notebooks export as a .zip archive (notebook.json + source files + chat history + notes). Importing restores everything locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Storage")
        .task { await calculateStorage() }
    }
    
    private var pathLabel: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("SourceDesk").path ?? "Unknown"
    }
    
    private func calculateStorage() async {
        var size: Int64 = 0
        for file in sourceFiles() {
            size += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        
        storageInfo.size = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private func sourceFiles() -> [URL] {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SourceDesk").appendingPathComponent("sources")
        guard let dir, FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    }
    
    private var freeDiskSpace: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }
    
    private func revealInFinder() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SourceDesk")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func openCacheFolder() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SourceDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @AppStorage("localOnlyMode") private var localOnlyMode = false
    @AppStorage("requireCloudConfirmation") private var requireCloudConfirmation = true
    
    var body: some View {
        Form {
            Section("Local-Only Mode") {
                Toggle("Restrict to local processing", isOn: $localOnlyMode)
                Text("When enabled, only local models (Ollama) and local sources are usable. Cloud features and web search are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Cloud Confirmation") {
                Toggle("Confirm before sending content to cloud AI", isOn: $requireCloudConfirmation)
                Text("SourceDesk shows a confirmation before sending excerpts of your sources to a cloud AI provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("How Your Data Flows") {
                DataFlowRow(
                    icon: "lock.fill",
                    color: .green,
                    title: "Local",
                    description: "Your sources and notebook data stay on this Mac. Nothing is uploaded by SourceDesk."
                )
                DataFlowRow(
                    icon: "arrow.up.circle",
                    color: .blue,
                    title: "Cloud AI",
                    description: "When you use OpenAI or Anthropic, the messages you send (including retrieved source excerpts) go to that provider's API."
                )
                DataFlowRow(
                    icon: "globe",
                    color: .orange,
                    title: "Web Search",
                    description: "When web search is on, your queries are sent to the selected search provider."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
    }
}

struct DataFlowRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { _, mode in
                    applyAppearance(mode)
                }
                
                Text("Choose how SourceDesk looks. System follows your Mac's appearance setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .onAppear {
            applyAppearance(appearanceMode)
        }
    }
    
    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}

// MARK: - Advanced

struct AppAdvancedSettingsView: View {
    @ObservedObject var aiManager: AIManager
    
    @AppStorage("chunkSize") private var chunkSize = 800
    @AppStorage("chunkOverlap") private var chunkOverlap = 100
    @AppStorage("retrievalCount") private var retrievalCount = 8
    @AppStorage("useEmbeddings") private var useEmbeddings = false
    @AppStorage("useOpenAIEmbeddings") private var useOpenAIEmbeddings = false
    @AppStorage("enableLogging") private var enableLogging = false
    @AppStorage("maxContextTokens") private var maxContextTokens = 16000
    
    var body: some View {
        Form {
            Section("Retrieval") {
                Stepper("Chunk size: \(chunkSize) tokens", value: $chunkSize, in: 200...4000, step: 100)
                Stepper("Chunk overlap: \(chunkOverlap) tokens", value: $chunkOverlap, in: 0...500, step: 50)
                Stepper("Retrieval count: \(retrievalCount) chunks", value: $retrievalCount, in: 3...30, step: 1)
            }
            
            Section("Embeddings") {
                Toggle("Use semantic search (embeddings)", isOn: $useEmbeddings)
                Toggle("Use OpenAI embeddings as fallback", isOn: $useOpenAIEmbeddings)
                
                if useEmbeddings {
                    Text("Embeddings improve retrieval quality. Sources are re-embedded after changing this setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !aiManager.ollamaAvailable {
                    Text("Ollama embedding models not detected. Install: ollama pull nomic-embed-text")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Section("Logging") {
                Toggle("Enable logging", isOn: $enableLogging)
            }
            
            Section("Context") {
                Stepper("Max context tokens: \(maxContextTokens)", value: $maxContextTokens, in: 2000...128000, step: 1000)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
    }
}

extension AIManager {
    var ollamaAvailable: Bool {
        ollamaIsAvailable
    }
}