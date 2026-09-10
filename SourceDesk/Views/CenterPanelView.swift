import SwiftUI
import SwiftData

struct CenterPanelView: View {
    @ObservedObject var container: ServiceContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var onAddSource: () -> Void
    
    var body: some View {
        Group {
            if container.notebookVM?.notebooks.isEmpty ?? true {
                WelcomeView(onNewNotebook: {
                    NotificationCenter.default.post(name: .createNotebook, object: nil)
                })
            } else if container.isReady {
                VStack(spacing: 0) {
                    Picker("", selection: $appState.centerTab) {
                        Text("Sources").tag("sources")
                        Text("Research").tag("research")
                        Text("Notes").tag("notes")
                        Text("Study Tools").tag("study")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    Divider()
                    
                    switch appState.centerTab {
                    case "sources":
                        if let sourceVM = container.sourceVM {
                            SourcesView(
                                sourceVM: sourceVM,
                                onAddSource: onAddSource
                            )
                        }
                    case "research":
                        if let chatVM = container.chatVM {
                            ResearchView(
                                chatVM: chatVM,
                                aiManager: appState.aiManager,
                                appState: appState
                            )
                        }
                    case "notes":
                        if let chatVM = container.chatVM {
                            NotesView(notebook: chatVM.currentNotebook)
                        }
                    case "study":
                        if let studyToolsVM = container.studyToolsVM {
                            StudyToolsView(viewModel: studyToolsVM)
                                .onAppear {
                                    studyToolsVM.configure(context: modelContext)
                                }
                        }
                    default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .animation(.default, value: container.notebookVM?.notebooks.isEmpty ?? true)
    }
}

extension ChatViewModel {
    var currentNotebook: NotebookModel? {
        notebook
    }
}