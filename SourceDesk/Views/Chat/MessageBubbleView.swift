import SwiftUI

struct MessageBubbleView: View {
    @Bindable var message: ChatMessageModel
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(message.provider ?? "AI Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                contentBody
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                
                if message.role == .user {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
            if message.role == .user, !message.isStreaming {
                Button("Delete") {
                    NotificationCenter.default.post(name: .deleteChatMessage, object: message.id)
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentBody: some View {
        if message.isError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Generation Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                FormattedMessageText(content: message.content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == .assistant {
            VStack(alignment: .leading, spacing: 10) {
                if message.isStreaming && message.content.isEmpty {
                    StreamingDotsView()
                } else {
                    FormattedMessageText(content: message.content)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                CitationBar(citations: message.citations)
            }
        } else {
            Text(message.content)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct FormattedMessageText: View {
    let content: String
    
    private var attributed: AttributedString {
        if let parsed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return parsed
        }
        return AttributedString(content)
    }
    
    var body: some View {
        Text(attributed)
    }
}

struct CitationBar: View {
    let citations: [Citation]
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sources")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(citations) { citation in
                            CitationPillView(citation: citation) {
                                appState.selectedRightPanelCitation = citation
                                appState.rightPanelTab = .citations
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CitationPillView: View {
    let citation: Citation
    let onOpen: () -> Void
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    Text("[\(citation.citationIndex)]")
                        .fontWeight(.bold)
                    Text(citation.sourceTitle)
                        .lineLimit(1)
                    if let page = citation.pageNumber {
                        Text("p.\(page)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("View citation details")
            
            if let urlString = citation.url, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Open source URL")
            }
        }
    }
}

struct StreamingDotsView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}