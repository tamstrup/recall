import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

@MainActor @Observable final class RecallStore {
    let persistence: RecordingPersistence
    private(set) var recordings: [Recording]
    let library: AudioLibrary
    private let transcriber: any TranscriptionEngine
    private let diarizer: any DiarizationEngine
    private let summarizer: any SummaryEngine
    private let logger = Logger(subsystem: "app.recall.mac", category: "Processing")
    private var queueTask: Task<Void, Never>?
    private var processingID: UUID?
    private(set) var importingCount = 0
    private(set) var summarizingIDs: Set<UUID> = []
    var selectedID: UUID?
    var alertMessage: String?

    init(persistence: RecordingPersistence, library: AudioLibrary,
         transcriber: any TranscriptionEngine, diarizer: any DiarizationEngine,
         summarizer: any SummaryEngine) {
        self.persistence = persistence
        self.recordings = persistence.recordings
        self.library = library
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.summarizer = summarizer
    }

    func recoverQueue() {
        guard queueTask == nil else { return }
        do {
            for recording in recordings where recording.status.isProcessing {
                recording.status = .queued
                recording.processingMessage = nil
                recording.processingProgress = nil
            }
            try persistence.save(recordings)
            startQueue()
        } catch { report(error) }
    }

    func showImporter() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose recordings to keep and process on this Mac."
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.importFiles(panel.urls) }
        }
    }

    func importFiles(_ urls: [URL]) async {
        importingCount += urls.count
        var errors: [String] = []
        for url in urls {
            do {
                let imported = try await library.importFile(url, existingHashes: Set(recordings.map(\.contentHash)))
                do {
                    let hash = imported.contentHash
                    if let existing = recordings.first(where: { $0.contentHash == hash }) {
                        try await library.remove(imported.audioFilename)
                        selectedID = existing.id
                    } else {
                        let recording = Recording(id: imported.id, originalFilename: imported.originalFilename,
                            audioFilename: imported.audioFilename, contentHash: hash, duration: imported.duration)
                        recordings.insert(recording, at: 0)
                        do { try persistence.save(recordings) } catch {
                            recordings.removeAll { $0.id == recording.id }
                            throw error
                        }
                        selectedID = recording.id
                        startQueue()
                    }
                } catch {
                    try? await library.remove(imported.audioFilename)
                    throw error
                }
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                logger.error("Audio import failed: \(error.localizedDescription, privacy: .private)")
            }
            importingCount -= 1
        }
        if !errors.isEmpty { alertMessage = errors.joined(separator: "\n\n") }
    }

    func retry(_ recording: Recording) {
        guard !recording.status.isProcessing else { return }
        recording.status = .queued
        recording.failureMessage = nil
        save()
        startQueue()
    }

    func retranscribe(_ recording: Recording) {
        guard !recording.status.isProcessing, !summarizingIDs.contains(recording.id) else { return }
        recording.needsTranscription = true
        retry(recording)
    }

    func delete(_ recording: Recording) async {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings.remove(at: index)
        do { try persistence.save(recordings) }
        catch {
            recordings.insert(recording, at: index)
            report(error)
            return
        }
        if processingID == recording.id { queueTask?.cancel() }
        if selectedID == recording.id { selectedID = recordings.first?.id }
        do { try await library.remove(recording.audioFilename) }
        catch {
            // Keep a visible library entry if its audio could not be removed.
            recording.status = .failed
            recording.processingProgress = nil
            recording.processingMessage = nil
            recording.failureMessage = "The audio file could not be deleted. Try deleting this recording again."
            recordings.insert(recording, at: min(index, recordings.count))
            save()
            report(error)
        }
    }

    private func startQueue() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.processingID = nil
                self.queueTask = nil
                if self.recordings.contains(where: { $0.status == .queued }) { self.startQueue() }
            }
            while !Task.isCancelled, let recording = self.recordings.sorted(by: { $0.importedAt < $1.importedAt }).first(where: { $0.status == .queued }) {
                self.processingID = recording.id
                await self.process(recording)
            }
        }
    }

    private func process(_ recording: Recording) async {
        let url = library.url(for: recording.audioFilename)
        let id = recording.id
        let progress: EngineProgress = { [weak self] message in
            await self?.setProgress(id, message: message)
        }
        do {
            if recording.segments.isEmpty || recording.needsTranscription {
                recording.status = .transcribing
                try persistence.save(recordings)
                let segments = try await transcriber.transcribe(url, progress: progress)
                try Task.checkCancellation()
                guard !segments.isEmpty else { throw RecallError(message: "No speech was found in this recording. You can still play the audio.") }
                recording.segments = segments
                recording.needsTranscription = false
                recording.diarizationComplete = false
                recording.speakers = []
                recording.summaries = []
                // Persist this stage independently; diarization failures must never lose it.
                try persistence.save(recordings)
            }
            if !recording.diarizationComplete {
                recording.status = .identifyingSpeakers
                try persistence.save(recordings)
                let turns = try await diarizer.identifySpeakers(url, progress: progress)
                try Task.checkCancellation()
                guard !turns.isEmpty else { throw RecallError(message: "No speakers could be identified. Your transcript is available; you can retry speaker detection.") }
                let aligned = SpeakerAlignment.align(recording.segments, turns: turns)
                recording.segments = aligned
                let ids = Set(aligned.compactMap(\.speakerID)).sorted()
                recording.speakers = ids.map { Speaker(id: $0, name: recording.speakerName($0)) }
                recording.diarizationComplete = true
            }
            recording.status = .ready
            recording.failureMessage = nil
            recording.processingMessage = nil
            recording.processingProgress = nil
            try persistence.save(recordings)
            logger.info("Recording processing completed")
        } catch {
            guard !Task.isCancelled, recordings.contains(where: { $0.id == id }) else { return }
            logger.error("Recording stage failed: \(error.localizedDescription, privacy: .private)")
            recording.status = .failed
            recording.processingMessage = nil
            recording.processingProgress = nil
            recording.failureMessage = error.localizedDescription
            save()
        }
    }

    private func setProgress(_ id: UUID, message: ProcessingProgress) {
        if let recording = recordings.first(where: { $0.id == id }) {
            recording.processingMessage = message.message
            recording.processingProgress = message
        }
    }

    func generateSummary(for recording: Recording, kind: SummaryKind) async {
        guard !summarizingIDs.contains(recording.id), !recording.segments.isEmpty,
              !recording.needsTranscription, !recording.status.isProcessing else { return }
        summarizingIDs.insert(recording.id)
        defer { summarizingIDs.remove(recording.id) }
        let transcript = recording.transcript
        do {
            let text = try await summarizer.summarize(transcript, kind: kind)
            guard recordings.contains(where: { $0.id == recording.id }) else { return }
            // Replace only after success. A failed regeneration preserves the previous result.
            var summaries = recording.summaries.filter { $0.kind != kind }
            summaries.append(GeneratedSummary(kind: kind, text: text))
            recording.summaries = summaries
            try persistence.save(recordings)
        } catch {
            if recordings.contains(where: { $0.id == recording.id }) { report(error) }
        }
    }

    func save() {
        do { try persistence.save(recordings) } catch { report(error) }
    }
    private func report(_ error: Error) {
        logger.error("Operation failed: \(error.localizedDescription, privacy: .private)")
        alertMessage = error.localizedDescription
    }
}
