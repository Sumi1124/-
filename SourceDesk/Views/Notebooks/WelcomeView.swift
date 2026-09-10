import SwiftUI

struct WelcomeView: View {
    var onNewNotebook: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            
            Text("Welcome to SourceDesk")
                .font(.largeTitle)
                .fontWeight(.semibold)
            
            Text("A local-first AI research notebook.\nCollect sources, ask questions grounded in your research, and study effectively.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            
            VStack(spacing: 8) {
                InfoFeatureRow(icon: "globe", title: "Collect", description: "Websites, PDFs, text, and folders")
                InfoFeatureRow(icon: "sparkles", title: "Understand", description: "Answers with citations grounded in your sources")
                InfoFeatureRow(icon: "lock.shield", title: "Keep private", description: "Local-first storage. Your data stays on your Mac.")
            }
            .frame(maxWidth: 360)
            
            Button(action: onNewNotebook) {
                Label("Create Your First Notebook", systemImage: "plus.square")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InfoFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}