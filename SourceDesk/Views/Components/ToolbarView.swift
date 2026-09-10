import SwiftUI

struct ToolbarView: View {
    @ObservedObject var aiManager: AIManager
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            // Offline indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isOnline ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(appState.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .help(appState.isOnline
                  ? "Internet connection available. Web features are enabled."
                  : "No internet connection. Local sources and local models still work.")
            
            Menu {
                providerMenu
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: providerIcon)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(aiManager.selectingProvider.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(aiManager.selectedModelName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 220)
            .help("Select AI provider and model")
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var providerMenu: some View {
        ForEach(AIProviderConfig.allCases) { config in
            Menu(config.displayName) {
                switch config {
                case .ollama:
                    Button("Ollama") {
                        aiManager.selectingProvider = .ollama
                        appState.saveProviderConfigs()
                    }
                    if aiManager.ollamaIsAvailable {
                        let models = aiManager.availableModelList
                        if models.isEmpty {
                            Text("No models installed locally")
                        } else {
                            ForEach(models, id: \.id) { model in
                                Button {
                                    aiManager.selectModel(model)
                                } label: {
                                    HStack {
                                        Text(model.name)
                                        if aiManager.ollama.selectedModel?.id == model.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Ollama not running")
                    }
                case .openai:
                    let models = AIManager.openAIModels
                    ForEach(models, id: \.id) { model in
                        Button {
                            aiManager.selectingProvider = .openai
                            aiManager.selectModel(model)
                            appState.saveProviderConfigs()
                        } label: {
                            HStack {
                                Text(model.name)
                                if aiManager.openai.selectedModel?.id == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                case .anthropic:
                    let models = AIManager.anthropicModels
                    ForEach(models, id: \.id) { model in
                        Button {
                            aiManager.selectingProvider = .anthropic
                            aiManager.selectModel(model)
                            appState.saveProviderConfigs()
                        } label: {
                            HStack {
                                Text(model.name)
                                if aiManager.anthropic.selectedModel?.id == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        Divider()
        
        Button("Open Settings…") {
            appState.selectedTab = .settings
            presentSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])
    }
    
    private var providerIcon: String {
        aiManager.selectingProvider.icon
    }
    
    private func presentSettings() {
        // Opens the SwiftUI Settings scene (cmd-,).
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}