import Testing
import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers
@testable import Recall

struct StubTranscriber: TranscriptionEngine {
    var fails = false
    func transcribe(_ audio: URL, progress: @escaping EngineProgress) async throws -> [TranscriptSegment] {
        if fails { throw RecallError(message: "Transcription unavailable") }
        return [TranscriptSegment(start: 0, end: 2, text: "We agreed to ship on Friday.")]
    }
}
struct StubDiarizer: DiarizationEngine {
    var fails = false
    func identifySpeakers(_ audio: URL, progress: @escaping EngineProgress) async throws -> [SpeakerTurn] {
        if fails { throw RecallError(message: "Speaker detection unavailable") }
        return [SpeakerTurn(start: 0, end: 2, speakerID: 4)]
    }
}
struct StubSummarizer: SummaryEngine {
    var fails = false
    func summarize(_ transcript: String, kind: SummaryKind) async throws -> String {
        if fails { throw RecallError(message: "Model unavailable") }
        return "Ship on Friday."
    }
}

@Suite @MainActor struct RecallTests {
    private func store(diarizationFails: Bool = false, transcriptionFails: Bool = false,
                       summaryFails: Bool = false, items: [Recording] = []) throws -> RecallStore {
        let persistence = try RecordingPersistence()
        try persistence.save(items)
        return RecallStore(persistence: persistence, library: AudioLibrary(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            transcriber: StubTranscriber(fails: transcriptionFails), diarizer: StubDiarizer(fails: diarizationFails),
            summarizer: StubSummarizer(fails: summaryFails))
    }
    private func recording() -> Recording {
        let recording = Recording(originalFilename: "Meeting.wav", audioFilename: "meeting.wav", contentHash: UUID().uuidString, duration: 2)
        return recording
    }
    private func awaitCompletion(_ recording: Recording) async throws {
        for _ in 0..<100 {
            if recording.status == .ready || recording.status == .failed { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Processing did not complete")
    }

    @Test func diarizationFailurePreservesTranscriptAndRetrySkipsTranscription() async throws {
        let item = recording()
        let first = try store(diarizationFails: true, items: [item])
        first.retry(item)
        try await awaitCompletion(item)
        #expect(item.status == .failed)
        #expect(item.segments.count == 1)
        #expect(item.failureMessage == "Speaker detection unavailable")
        // A transcriber that always fails proves that retry resumes at diarization.
        let retry = RecallStore(persistence: first.persistence, library: first.library,
            transcriber: StubTranscriber(fails: true), diarizer: StubDiarizer(), summarizer: StubSummarizer())
        retry.retry(item)
        try await awaitCompletion(item)
        #expect(item.status == .ready)
        #expect(item.speakers.count == 1)
        #expect(item.segments.first?.speakerID == 0)
    }

    @Test func failureDoesNotBlockNextRecording() async throws {
        let first = recording()
        let second = recording()
        let store = try store(transcriptionFails: true, items: [first, second])
        second.segments = [TranscriptSegment(start: 0, end: 1, text: "Already transcribed")]
        store.recoverQueue()
        try await awaitCompletion(second)
        #expect(first.status == .failed)
        #expect(second.status == .ready)
    }

    @Test func interruptedProcessingResumes() async throws {
        let item = recording()
        let store = try store(items: [item])
        item.status = .transcribing
        store.recoverQueue()
        try await awaitCompletion(item)
        #expect(item.status == .ready)
    }

    @Test func renameUpdatesEveryOccurrenceAndSummaryInput() throws {
        let item = recording()
        item.speakers = [Speaker(id: 0, name: "Speaker 1")]
        item.segments = [TranscriptSegment(start: 0, end: 1, text: "First", speakerID: 0),
                         TranscriptSegment(start: 1, end: 2, text: "Second", speakerID: 0)]
        item.renameSpeaker(0, to: "  Patrick  ")
        #expect(item.transcript.components(separatedBy: "Patrick").count == 3)
        item.renameSpeaker(0, to: "  ")
        #expect(item.speakerName(0) == "Patrick")
    }

    @Test func failedSummaryPreservesEarlierVersion() async throws {
        let item = recording()
        let store = try store(summaryFails: true, items: [item])
        item.segments = [TranscriptSegment(start: 0, end: 2, text: "Hello")]
        item.summaries = [GeneratedSummary(kind: .summary, text: "Existing summary")]
        await store.generateSummary(for: item, kind: .summary)
        #expect(item.summaries.first?.text == "Existing summary")
        #expect(store.alertMessage == "Model unavailable")
        #expect(store.summarizingIDs.isEmpty)
    }

    @Test func diskPersistenceRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let persistence = try RecordingPersistence(url: url)
        let item = Recording(originalFilename: "Meeting.m4a", audioFilename: "audio.m4a", contentHash: "abc", duration: 3)
        item.segments = [TranscriptSegment(start: 0.5, end: 2.8, text: "A decision", speakerID: 0)]
        item.speakers = [Speaker(id: 0, name: "Patrick")]
        item.summaries = [GeneratedSummary(kind: .decisions, text: "Ship it")]
        try persistence.save([item])
        let reopened = try RecordingPersistence(url: url)
        let loaded = try #require(reopened.recordings.first)
        #expect(loaded.transcript.contains("Patrick"))
        #expect(loaded.segments.first?.start == 0.5)
        #expect(loaded.summaries.first?.text == "Ship it")
    }

    @Test func finderDropMultiImportDedupAndInvalidFile() async throws {
        let store = try store()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try makeAudio(at: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: store.library.root)
        }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(source.dataRepresentation, nil)
            return nil
        }
        let urls = try await AudioDrop.urls(from: [provider, provider])
        #expect(urls == [source, source])
        await store.importFiles(urls)
        let saved = store.recordings
        #expect(saved.count == 1)
        let item = try #require(saved.first)
        try await awaitCompletion(item)
        #expect(item.status == .ready)
        #expect(FileManager.default.fileExists(atPath: store.library.url(for: item.audioFilename).path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.library.root.path).count == 1)
        let invalid = source.deletingPathExtension().appendingPathExtension("mp3")
        try Data("not audio".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }
        await store.importFiles([invalid])
        #expect(store.alertMessage != nil)
        #expect(store.recordings.count == 1)
        #expect(store.importingCount == 0)
    }

    @Test func playbackAndSeek() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try makeAudio(at: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let player = AudioPlayer()
        player.load(source)
        #expect(player.errorMessage == nil)
        #expect(abs(player.duration - 1) < 0.02)
        player.seek(0.5)
        #expect(player.currentTime == 0.5)
        player.seek(400)
        #expect(player.currentTime <= player.duration)
        player.stop()
    }

    @Test func silenceFailsBeforeModelDownload() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        memset(buffer.floatChannelData![0], 0, 16_000 * MemoryLayout<Float>.size)
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }
        #expect(try !AudioSignal.hasAudibleSamples(source))
        do {
            _ = try await WhisperTranscriptionEngine(models: source.deletingPathExtension()).transcribe(source) { _ in }
            Issue.record("Silence should fail before attempting a model download")
        } catch {
            #expect(error.localizedDescription.contains("silent"))
        }
    }

    private func makeAudio(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for frame in 0..<16_000 { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.08) * 0.1) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

@Suite struct TranscriptTests {
    @Test func wordAlignmentSplitsAtSpeakerChangeAndKeepsUnknowns() {
        let segment = TranscriptSegment(start: 0, end: 4, text: "Hello there everyone", words: [
            TranscriptWord(start: 0, end: 1, text: " Hello"),
            TranscriptWord(start: 1, end: 2, text: " there"),
            TranscriptWord(start: 3, end: 4, text: " everyone")
        ])
        let aligned = SpeakerAlignment.align([segment], turns: [
            SpeakerTurn(start: 0, end: 1, speakerID: 8), SpeakerTurn(start: 1, end: 2, speakerID: 3)
        ])
        #expect(aligned.map(\.speakerID) == [0, 1, nil])
        #expect(aligned.map(\.text) == ["Hello", "there", "everyone"])
        #expect(aligned.last?.end == 4)
    }
    @Test func chunkingPreservesUnicodeAndAllContent() {
        let text = String(repeating: "Møde i morgen. 日本語の会話。👨‍👩‍👧‍👦\n", count: 500)
        let chunks = SummaryChunks.split(text)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf8.count <= 2400 })
    }
    @Test func timestampsHandleHoursAndInvalidValues() {
        #expect(TimeLabel.format(3661) == "1:01:01")
        #expect(TimeLabel.format(.nan) == "0:00")
        #expect(TimeLabel.format(-30) == "0:00")
    }
}

@Suite struct LocalModelIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECALL_TEST_AUDIO"] != nil))
    func realLocalSpeechPipeline() async throws {
        let env = ProcessInfo.processInfo.environment
        let audio = URL(fileURLWithPath: try #require(env["RECALL_TEST_AUDIO"]))
        let models = URL(fileURLWithPath: try #require(env["RECALL_TEST_MODELS"]))
        let transcriber = WhisperTranscriptionEngine(models: models,
            modelName: env["RECALL_TEST_MODEL"] ?? "large-v3-v20240930_626MB")
        let segments = try await transcriber.transcribe(audio) { print("INFERENCE: \($0)") }
        #expect(!segments.isEmpty)
        #expect(segments.map(\.text).joined().lowercased().contains("friday"))
        let turns = try await SpeakerDiarizationEngine(models: models).identifySpeakers(audio) { print("INFERENCE: \($0)") }
        #expect(!turns.isEmpty)
        let aligned = SpeakerAlignment.align(segments, turns: turns)
        #expect(!aligned.compactMap(\.speakerID).isEmpty)
        print("INFERENCE: \(segments.count) transcript segments; \(Set(aligned.compactMap(\.speakerID)).count) speakers")
        print("INFERENCE TRANSCRIPT: \(aligned.map(\.text).joined(separator: " "))")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECALL_TEST_AUDIO"] != nil))
    func commonAudioFormatsImport() async throws {
        let env = ProcessInfo.processInfo.environment
        let fixture = URL(fileURLWithPath: try #require(env["RECALL_TEST_AUDIO"])).deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = AudioLibrary(root: root)
        for filename in ["meeting.wav", "meeting.m4a", "silence.mp3"] {
            let imported = try await library.importFile(fixture.appendingPathComponent(filename))
            #expect(imported.duration > 0)
            #expect(FileManager.default.fileExists(atPath: library.url(for: imported.audioFilename).path))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECALL_TEST_SUMMARY"] == "1"))
    func realAppleSummaryOrUnavailableState() async throws {
        if let reason = SummaryAvailability.unavailableReason {
            print("SUMMARY UNAVAILABLE: \(reason)")
            return
        }
        let transcript = "Patrick · 0:00\nWe have decided to release the first version on Friday. I will write the release notes tomorrow.\n\nAlex · 0:10\nI will test the audio import on Thursday."
        for kind in SummaryKind.allCases {
            let summary = try await AppleSummaryEngine().summarize(transcript, kind: kind)
            #expect(!summary.isEmpty)
            if kind == .decisions {
                #expect(summary.lowercased().contains("friday"))
                #expect(!summary.lowercased().contains("thursday"))
            }
            if kind == .actionItems {
                #expect(summary.contains("Patrick"))
                #expect(summary.contains("Alex"))
            }
            print("LOCAL \(kind.rawValue): \(summary)")
        }
    }
}
