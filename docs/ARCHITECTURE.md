# SourceDesk Architecture

SourceDesk is a macOS application written in Swift with SwiftUI + SwiftData. It
uses a classic three-column layout (sidebar / content / inspector) and a
service layer that separates pure algorithms from UI and persistence.

## High-level flow

```
Add Source ─► SourceIngestionService ─► extractedText on SourceModel
                    │
                    ▼
          ChunkingService (TextChunker) ─► SourceChunkModel[]
                    │
                    ▼
          EmbeddingService (optional) ─► EmbeddingModel[] (Float vectors)

Ask a question ─► ChatViewModel ─► RAGPipeline.retrieve
                    │                    ├── VectorStore (semantic/keyword)
                    │                    └── SearchManager (optional web)
                    ▼
            buildSystemPrompt "[Source 1] …", "[Web 1] …"
                    ▼
            AIProvider.generate (Ollama / OpenAI / Anthropic)
                    ▼
            parseCitations → Citation[] stored as JSON on the message
```

## Layering

### 1. Models (`Models/`)

SwiftData `@Model` classes:

| Type | Purpose |
| --- | --- |
| `NotebookModel` | the research notebook; owns sources, chats, notes |
| `SourceModel`, `SourceChunkModel` | a collected source and its chunks |
| `EmbeddingModel` | Float vector per chunk for semantic search |
| `ChatSessionModel`, `ChatMessageModel` | research sessions + messages |
| `NotebookNoteModel` | notes, including study-tool output |

`Models/Types.swift` deliberately contains **no SwiftData** — `MessageRole` and
`Citation` are shared with the AI layer (which must stay importable by unit
tests without a Store).

### 2. AI layer (`Services/AI/`)

- `AIProvider` (protocol): `name`, `isLocal`, async `isAvailable` /
  `availableModels`, `selectedModel`, `generate`, `stream`, `embed`.
- `OllamaProvider`: talks to the local Ollama daemon. Lists installed models via
  `/api/tags`; **never pulls or downloads models**. `diagnose()` returns a
  `OllamaDiagnostic` with human-readable status.
- `OpenAIProvider` / `AnthropicProvider`: cloud providers; keys read/written via
  `KeychainService`.
- `AIManager`: app-wide provider/model selection, persisted in UserDefaults.

### 3. Ingestion (`Services/Ingestion/`)

- `WebDownloader` (actor): fetches pages and respects `robots.txt`
  (`RobotsTxtParser`), keeping the parsing logic dependency-free.
- `ContentExtractor`: pulls title / meta description / main text out of HTML.
- `DocumentExtractor`: PDF (PDFKit), plain text, DOCX (via `unzip`), with
  `extractTextFile` being async.
- `SourceIngestionService`: orchestrates all three; copies local files into
  `Application Support/SourceDesk/sources` so the originals can move/delete.

### 4. RAG (`Services/RAG/`)

- `TextChunker` (`Utilities/TextProcessing.swift`): token-estimating chunker
  that splits oversized single paragraphs by sentence boundary then hard
  token-bound.
- `VectorStore`: semantic search (cosine similarity over stored embeddings) with
  keyword-search fallback (pure `VectorMath.swift`).
- `RAGPipeline`: decides chunk retrieval + optional web results, builds the
  numbered `[Source N]` / `[Web N]` prompt.

### 5. Study tools (`Services/StudyToolsService.swift`)

Ten prompt-driven generators; output can be saved into the notebook as
`NotebookNoteModel`.

### 6. Storage (`Services/Storage/`)

- `KeychainService`: clear/read/delete secret API keys.
- `NotebookExporter`: `notebook.json` manifest + source files archived with the
  macOS `ditto` tool (no third-party zip dependency).

## UI (`Views/`)

`ContentView` hosts a `NavigationSplitView`:

- **Sidebar**: notebooks, favorites, recent; new/rename/export/import via context
  menu and toolbar.
- **Content**: segmented Sources / Research / Notes / Study Tools, driven by
  `ServiceContainer` (created in `ContentView`, configured in `.onAppear` with
  `modelContext` + shared `AIManager` + `SearchManager`).
- **Inspector**: source details, citation details, notebook overview, and a web
  search field.

`AppState` (an `ObservableObject`) holds global UI state: selected notebook,
selected source, `SearchMode`, right-panel tab, online status (via
`NWPathMonitor`), and owns the single shared `AIManager` + `SearchManager`.

## Concurrency

- Everything touching SwiftData or UI is `@MainActor`.
- Network work (download, AI calls, search) runs in `async`/`await` off the main
  actor, hopping back for model mutations.
- Long operations post progress through `@Published` view-model state.

## Persistence & privacy

- SwiftData store at `~/Library/Application Support/SourceDesk/` (App Group
  `group.com.sourcedesk.app` used when the entitlement is present, otherwise a
  per-app store fallback keeps the app launchable in unsigned dev builds).
- API keys live in Keychain, never in the store or logs.
- Local-Only Mode and cloud-confirmation are enforced in the **view models**
  (`ChatViewModel`, `StudyToolsViewModel`) and surfaced in the UI, keeping the AI
  layer provider-agnostic.

## Verification without Xcode

Pure modules (`Utilities/`, `VectorMath`, `Types`, search providers, provider
protocols) compile with the Command Line Toolchain:

```bash
xcrun swiftc -typecheck -sdk $(xcrun --sdk macosx --show-sdk-path) Usages/…
```

SwiftData `@Model` files require Xcode's build system and must be verified by
building the app in Xcode.