import SwiftUI

struct StudyToolsView: View {
    @ObservedObject var viewModel: StudyToolsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Study Tools")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StudyToolType.allCases) { tool in
                            StudyToolChoiceView(
                                tool: tool,
                                isSelected: viewModel.selectedTool == tool
                            ) {
                                viewModel.selectedTool = tool
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                sourceSelector
                    .padding(.horizontal)
                
                Divider()
                
                outputArea
            }
            .padding(.top, 10)
        }
    }
    
    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
                Spacer()
                Text(viewModel.selectedSources.isEmpty ? "No sources" : "\(viewModel.selectedSources.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if viewModel.selectedSources.isEmpty {
                Text("Add sources to your notebook to generate study material.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.selectedSources) { source in
                            let isSelected = viewModel.selectedSourceIDs.contains(source.id) || viewModel.selectedSourceIDs.isEmpty
                            Button {
                                toggleSource(source)
                            } label: {
                                Text(source.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    private func toggleSource(_ source: SourceModel) {
        if viewModel.selectedSourceIDs.contains(source.id) {
            viewModel.selectedSourceIDs.remove(source.id)
            if viewModel.selectedSourceIDs.isEmpty && viewModel.selectedSources.count == 1 {
                viewModel.selectedSourceIDs = []
            }
        } else {
            viewModel.selectedSourceIDs = viewModel.selectedSources
                .filter { $0.id != source.id }
                .map(\.id)
                .reduce(into: Set<UUID>()) { $0.insert($1) }
            viewModel.selectedSourceIDs.insert(source.id)
        }
    }
    
    private var outputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.generate() }
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                }
                .controlSize(.large)
                .disabled(!viewModel.canGenerate)
                
                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !viewModel.outputText.isEmpty {
                    Button("Copy") { viewModel.copyToClipboard() }
                    Button("Save to Notes") { viewModel.saveToNotebook() }
                    Button("Clear") { viewModel.clear() }
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            
            if viewModel.outputText.isEmpty && !viewModel.isGenerating {
                toolDescription
            } else {
                ScrollView {
                    Text(viewModel.outputText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    private var toolDescription: some View {
        VStack(spacing: 10) {
            Text(viewModel.selectedTool.rawValue)
                .font(.title3)
                .fontWeight(.semibold)
            Text(viewModel.selectedTool.description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Image(systemName: viewModel.selectedTool.icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct StudyToolChoiceView: View {
    let tool: StudyToolType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: tool.icon)
                    .font(.title3)
                Text(tool.rawValue)
                    .font(.caption)
            }
            .frame(width: 84, height: 56)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}