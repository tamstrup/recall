import SwiftUI
import AppKit

@main struct RecallApp: App {
    @State private var store: RecallStore?
    private let startupError: String?

    init() {
        do {
            #if DEBUG
            if PreviewCapture.output != nil {
                _store = State(initialValue: try PreviewCapture.makeStore())
                startupError = nil
                NSApplication.shared.setActivationPolicy(.regular)
                return
            }
            #endif
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recall", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let persistence = try RecordingPersistence(url: base.appendingPathComponent("Recall.sqlite"))
            let models = base.appendingPathComponent("Models", isDirectory: true)
            _store = State(initialValue: RecallStore(persistence: persistence,
                library: AudioLibrary(root: base.appendingPathComponent("Audio", isDirectory: true)),
                transcriber: WhisperTranscriptionEngine(models: models),
                diarizer: SpeakerDiarizationEngine(models: models), summarizer: AppleSummaryEngine()))
            startupError = nil
        } catch {
            _store = State(initialValue: nil)
            startupError = error.localizedDescription
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Recall", id: "inbox") {
            if let store {
                InboxView().environment(store)
                    .background(WindowChrome().allowsHitTesting(false))
                    .task {
                        store.recoverQueue()
                        #if DEBUG
                        await PreviewCapture.capture(store: store)
                        #endif
                    }
                    .onOpenURL { url in Task { await store.importFiles([url]) } }
            } else {
                ContentUnavailableView {
                    Label("Recall couldn’t open its library", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(startupError ?? "Unknown storage error")
                    Text("Your existing files have not been removed. Quit Recall and check available disk space and access to Application Support/Recall.")
                }.frame(width: 650, height: 400)
            }
        }
        .defaultSize(width: 1080, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Recordings…") { store?.showImporter() }
                    .keyboardShortcut("o").disabled(store == nil)
            }
        }
    }
}
