import SwiftUI

struct ResearchView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var aiManager: AIManager
    @ObservedObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @State private var inputText = ""
    @State private var showSessionList = false
    @State private var pendingCloudSend = false
    @State private var confirmCloud = false
    
    var body: some View {
        VStack(spacing: 0) {
            researchHeader
            
            Divider()
            
            if chatVM.sessions.isEmpty {
                ResearchEmptyState {
                    chatVM.newSession()
                }
            } else {
                messageList
                Divider()
                inputBar
            }
        }
        .onAppear {
            chatVM.configure(context: modelContext, notebook: chatVM.notebook)
        }
        .alert("Send to \(aiManager.selectedProvider.name)?", isPresented: $confirmCloud) {
            Button("Send") {
                performSend()
            }
            Button("Cancel", role: .cancel) {
                pendingCloudSend = false
            }
        } message: {
            Text("Your question and the relevant excerpts from your sources will be sent to \(aiManager.selectedProvider.name). This content leaves your Mac.")
        }
    }
    
    private var researchHeader: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { showSessionList.toggle() }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .help("Chat sessions")
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Research")
                    .font(.title2)
                    .fontWeight(.semibold)
                if let session = currentSession {
                    Text(session.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            SearchModePicker(searchMode: $appState.searchMode)
            
            if let contextLength = aiManager.selectedModelContextLength {
                Text("\(contextLength.formatted()) ctx")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            if showSessionList {
                sessionListSheet
            }
        }
    }
    
    private var sessionListSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Button("New", action: { chatVM.newSession(); showSessionList = false })
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(chatVM.sessions) { session in
                        HStack {
                            Text(session.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            session.id == chatVM.selectedSessionID
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            chatVM.selectSession(session)
                            showSessionList = false
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                chatVM.deleteSession(session)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 260)
        }
        .frame(maxWidth: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        .shadow(radius: 12)
        .padding(.top, 46)
        .transition(.opacity)
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatVM.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: chatVM.messages.count) {
                if let last = chatVM.messages.last, chatVM.messages.count > 0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatVM.messages.last?.content ?? "") {
                if let last = chatVM.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $inputText)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .onSubmit {
                    send()
                }
                .disabled(chatVM.isGenerating)
            
            if chatVM.isGenerating {
                Button {
                    chatVM.stopGenerating()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .frame(width: 18, height: 18)
                        .padding(8)
                        .background(Color.secondary.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help("Stop generating (Esc)")
                .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 18, height: 18)
                        .padding(8)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘Return)")
            }
        }
        .padding()
    }
    
    private var currentSession: ChatSessionModel? {
        guard let id = chatVM.selectedSessionID else { return nil }
        return chatVM.sessions.first { $0.id == id }
    }
    
    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let requireConfirmation = UserDefaults.standard.bool(forKey: "requireCloudConfirmation")
        let providerIsCloud = !aiManager.selectedProvider.isLocal
        
        if requireConfirmation && providerIsCloud {
            let providerKey = "cloudConfirmed_\(aiManager.selectedProvider.name)"
            if UserDefaults.standard.bool(forKey: providerKey) {
                performSend()
                return
            }
            pendingCloudSend = true
            confirmCloud = true
            return
        }
        
        performSend()
    }
    
    private func performSend() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatVM.sendMessage(text, searchMode: appState.searchMode, isOnline: appState.isOnline)
        inputText = ""
        if pendingCloudSend {
            UserDefaults.standard.set(true, forKey: "cloudConfirmed_\(aiManager.selectedProvider.name)")
            pendingCloudSend = false
        }
    }
}

struct SearchModePicker: View {
    @Binding var searchMode: AppState.SearchMode
    
    var body: some View {
        Menu {
            ForEach(AppState.SearchMode.allCases, id: \.self) { mode in
                Button {
                    searchMode = mode
                } label: {
                    if searchMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: searchModeIcon)
                Text(searchMode.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .menuIndicator(.hidden)
        .help("Search mode: decide what the AI searches")
    }
    
    private var searchModeIcon: String {
        switch searchMode {
        case .notebookOnly: return "folder"
        case .notebookAndWeb: return "folder.badge.globe"
        case .webOnly: return "globe"
        }
    }
}

struct ResearchEmptyState: View {
    var onNewChat: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            
            Text("Ask Questions About Your Sources")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("The AI will search your notebook's sources and answer with citations.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            
            Button(action: onNewChat) {
                Label("New Research Session", systemImage: "plus.bubble")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}