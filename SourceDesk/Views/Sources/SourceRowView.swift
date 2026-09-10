import SwiftUI

struct SourceRowView: View {
    let source: SourceModel
    let isSelected: Bool
    
    private var statusColor: Color {
        switch source.status {
        case .ready: return .green
        case .error: return .red
        case .pending, .downloading, .processing, .indexing: return .orange
        case .incomplete: return .yellow
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor.opacity(0.12))
                .frame(width: 34, height: 40)
                .overlay(
                    Image(systemName: source.sourceType.icon)
                        .font(.body)
                        .foregroundStyle(statusColor)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(source.sourceType.displayName)
                    if let _ = source.metadata.pageCount {
                        Text("·")
                        Text("\(source.metadata.pageCount ?? 0) pages")
                    }
                    if source.chunkCount > 0 {
                        Text("·")
                        Text("\(source.chunkCount) chunks")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            if source.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            
            if source.status == .ready, !source.hasContent {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            switch source.status {
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

struct SourcesEmptyState: View {
    var onAddSource: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            
            Text("No Sources Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Add websites, PDFs, or text documents to build your research collection.\nSources are stored locally on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(maxWidth: 340)
            
            Button(action: onAddSource) {
                Label("Add Source", systemImage: "plus")
            }
            .controlSize(.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProcessingBannerView: View {
    let message: String
    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            
            Text(message)
                .font(.callout)
                .lineLimit(1)
            
            Spacer()
            
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                    .help("Stop this operation")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }
}

struct IngestionErrorsBanner: View {
    let errors: [SourceViewModel.SourceError]
    var onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Some sources could not be added")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("Dismiss", action: onClear)
                    .controlSize(.small)
            }
            ForEach(errors) { error in
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.sourceTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }
}