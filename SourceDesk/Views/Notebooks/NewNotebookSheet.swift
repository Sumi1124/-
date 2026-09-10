import SwiftUI

struct NewNotebookSheet: View {
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var subtitle = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Notebook")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Industrial Revolution", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("What is this notebook about?", text: $subtitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    onCreate(title.trimmingCharacters(in: .whitespacesAndNewlines), subtitle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}