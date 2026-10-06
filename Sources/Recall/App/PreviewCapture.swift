#if DEBUG
import AppKit
import SwiftUI
import AVFoundation

// Explicit developer-only screenshot mode, isolated from the user's library.
@MainActor enum PreviewCapture {
    static var output: String? { ProcessInfo.processInfo.environment["RECALL_CAPTURE_UI"] }
    static var sample: Bool { ProcessInfo.processInfo.environment["RECALL_SAMPLE_UI"] == "1" }
    static func makeStore() throws -> RecallStore {
        let persistence = try RecordingPersistence()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Recall-UI-Preview")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if sample {
            let audio = root.appendingPathComponent("sample.wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000 * 30)!
            buffer.frameLength = buffer.frameCapacity
            memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            try file.write(from: buffer)
            let item = Recording(originalFilename: "Friday planning.m4a", audioFilename: "sample.wav", contentHash: "preview", duration: 30)
            item.title = "Friday planning"
            item.status = .ready
            item.diarizationComplete = true
            item.speakers = [Speaker(id: 0, name: "Patrick"), Speaker(id: 1, name: "Speaker 2")]
            item.segments = [
                TranscriptSegment(start: 0, end: 8, text: "Let’s keep the first version small. I’d like to import a recording and come back to a useful transcript.", speakerID: 0),
                TranscriptSegment(start: 8, end: 16, text: "Agreed. We should make sure the audio stays on the Mac, and that I can rename the speakers afterwards.", speakerID: 1),
                TranscriptSegment(start: 16, end: 24, text: "I’ll try it with a few recordings on Friday. Then we can decide what needs attention before sharing it.", speakerID: 0),
                TranscriptSegment(start: 24, end: 30, text: "Perfect. Let’s write down the decisions and keep the rest for later.", speakerID: 1)
            ]
            item.summaries = [GeneratedSummary(kind: .summary, text: "Keep the first version focused on importing recordings, reading transcripts, and renaming speakers. Audio stays on the Mac. Patrick will test a few recordings on Friday before the team decides what to improve.")]
            try persistence.save([item])
        }
        let store = RecallStore(persistence: persistence, library: AudioLibrary(root: root),
            transcriber: WhisperTranscriptionEngine(models: root), diarizer: SpeakerDiarizationEngine(models: root),
            summarizer: AppleSummaryEngine())
        store.selectedID = store.recordings.first?.id
        return store
    }
    static func capture() async {
        guard let output else { return }
        try? await Task.sleep(for: .seconds(2))
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }), let view = window.contentView else { return }
        if ProcessInfo.processInfo.environment["RECALL_SMALL_UI"] == "1" {
            window.setContentSize(NSSize(width: 800, height: 540))
        }
        if ProcessInfo.processInfo.environment["RECALL_DARK_UI"] == "1" {
            window.appearance = NSAppearance(named: .darkAqua)
        } else { window.appearance = NSAppearance(named: .aqua) }
        try? await Task.sleep(for: .milliseconds(500))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do { try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output)) }
        catch { print("Snapshot failed: \(error)") }
        NSApplication.shared.terminate(nil)
    }
}
#endif
