import SwiftUI
import UniformTypeIdentifiers

struct AddSourceSheet: View {
    @ObservedObject var sourceVM: SourceViewModel
    @Environment(\.dismiss) private var dismiss
    
    enum Mode: String, CaseIterable {
        case website = "Website"
        case file = "Files"
        case text = "Pasted Text"
    }
    
    @State private var mode: Mode = .website
    @State private var urlString = ""
    @State private var pastedText = ""
    @State private var textTitle = ""
    @State private var selectedFileURLs: [URL] = []
    @State private var errorMessage: String?
    @State private var isFilePickerPresented = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Source")
                .font(.title2)
                .fontWeight(.semibold)
            
            Picker("Source type", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            
            switch mode {
            case .website:
                websiteForm
            case .file:
                fileForm
            case .text:
                textForm
            }
            
            if let errorMessage {
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
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: submit) {
                    Text("Add")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [
                .pdf, .plainText, .text, .png, .jpeg, .html, .rtf,
                UTType(filenameExtension: "md") ?? .plainText,
                UTType(filenameExtension: "docx") ?? .plainText,
                UTType(filenameExtension: "markdown") ?? .plainText
            ],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURLs = urls
            case .failure(let error):
                errorMessage = "Could not add file: \(error.localizedDescription)"
            }
        }
    }
    
    private var websiteForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("https://example.com/article", text: $urlString)
                    .textFieldStyle(.roundedBorder)
            }
            
            Text("The app will download the page, extract the readable content, and store it locally on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !urlString.isEmpty && !isValidURL(urlString) {
                Label("Enter a valid http or https URL.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
    
    private var fileForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Files…") {
                    isFilePickerPresented = true
                }
                .controlSize(.large)
                
                Text(selectedFileURLs.isEmpty ? "No files selected" : "\(selectedFileURLs.count) file(s)")
                    .foregroundStyle(.secondary)
            }
            
            if !selectedFileURLs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(selectedFileURLs, id: \.absoluteString) { url in
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(url))
                                Text(url.lastPathComponent)
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            
            Text("Supported: PDF, TXT, Markdown, HTML, DOCX. Files are stored locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var textForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $textTitle)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $pastedText)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            
            Text("Paste any text content. It will be stored locally as a source.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var canSubmit: Bool {
        switch mode {
        case .website:
            return isValidURL(urlString)
        case .file:
            return !selectedFileURLs.isEmpty
        case .text:
            return !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !textTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    
    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "md", "markdown": return "doc.text"
        case "docx": return "doc.badge.gearshape"
        case "html", "htm": return "code"
        default: return "doc.plaintext"
        }
    }
    
    private func submit() {
        switch mode {
        case .website:
            sourceVM.addFromURL(urlString)
        case .file:
            sourceVM.addFromFiles(urls: selectedFileURLs)
        case .text:
            sourceVM.addFromText(pastedText, title: textTitle)
        }
        
        dismiss()
    }
}