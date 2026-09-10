import SwiftUI
import SwiftData

@main
struct SourceDeskApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NotebookModel.self,
            SourceModel.self,
            SourceChunkModel.self,
            ChatMessageModel.self,
            ChatSessionModel.self,
            NotebookNoteModel.self,
            EmbeddingModel.self
        ])
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupStoreURLIdentifier: "group.com.sourcedesk.app"
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The App Group entitlement may not be configured (e.g. unsigned
            // dev builds). Fall back to the app-local store so the app still launches.
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
.frame(minWidth: 900, minHeight: 600)
        .onAppear {
            applySavedAppearance()
        }
    }
    .defaultSize(width: 1200, height: 800)
    
    #if os(macOS)
    Settings {
        SettingsView()
            .environmentObject(appState)
    }
    #endif
        
        CommandGroup(replacing: .newItem) {
            Button("New Notebook") {
                NotificationCenter.default.post(name: .createNotebook, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Add Source") {
                NotificationCenter.default.post(name: .addSource, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command])
            Button("Command Palette…") {
                NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }
    }
    
    private func applySavedAppearance() {
        let mode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
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

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let createNotebook = Notification.Name("createNotebook")
    static let addSource = Notification.Name("addSource")
    static let selectNotebook = Notification.Name("selectNotebook")
    static let deleteChatMessage = Notification.Name("deleteChatMessage")
    static let toggleCommandPalette = Notification.Name("toggleCommandPalette")
}
