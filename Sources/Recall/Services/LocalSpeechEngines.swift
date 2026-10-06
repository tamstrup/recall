import Foundation
import ArgmaxCore
import WhisperKit
import SpeakerKit

actor WhisperTranscriptionEngine: TranscriptionEngine {
    let models: URL
    let modelName: String
    init(models: URL, modelName: String = "large-v3-v20240930_626MB") {
        self.models = models
        self.modelName = modelName
    }
    func transcribe(_ audio: URL, progress: @escaping EngineProgress) async throws -> [TranscriptSegment] {
        guard try AudioSignal.hasAudibleSamples(audio) else {
            throw RecallError(message: "This recording is silent. You can still play it, but there is no audible speech to transcribe.")
        }
        let receipt = models.appendingPathComponent("recall-whisper-\(modelName).json")
        let cachedFolder = (try? Data(contentsOf: receipt)).flatMap { try? JSONDecoder().decode(String.self, from: $0) }
        var localFolder = cachedFolder.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        if localFolder == nil {
            let folder = try await withModelDownloadProgress(message: "Downloading transcription model · 1 of 2", progress: progress) { callback in
                try await WhisperKit.download(variant: modelName, downloadBase: models, progressCallback: callback)
            }
            localFolder = folder.path
        }
        await progress(ProcessingProgress(message: "Preparing transcription model for this Mac",
            detail: "Model files are on this Mac. First-time preparation can take several minutes. Transcription starts automatically."))
        let kit = try await WhisperKit(WhisperKitConfig(model: modelName, downloadBase: models,
            modelFolder: localFolder, verbose: false, prewarm: true, load: true, download: false))
        do {
            try Task.checkCancellation()
            await progress(ProcessingProgress(message: "Transcribing on your Mac",
                detail: "Model setup is complete. Your recording is now being transcribed locally."))
            let results = try await kit.transcribe(
                audioPath: audio.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                // WhisperKit defaults to an English prefill with detection off.
                // Explicit detection preserves the language actually spoken.
                decodeOptions: DecodingOptions(verbose: false, task: .transcribe,
                    detectLanguage: true, skipSpecialTokens: true, wordTimestamps: true)
            )
            let segments = results.flatMap(\.segments).compactMap { segment -> TranscriptSegment? in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TranscriptSegment(start: Double(segment.start), end: Double(segment.end), text: text,
                    words: (segment.words ?? []).map {
                        TranscriptWord(start: Double($0.start), end: Double($0.end), text: $0.word)
                    })
            }
            // Save the resolved path only after the models and tokenizer worked. Future
            // launches can open them directly without a model-list network request.
            if let folder = kit.modelFolder {
                try? JSONEncoder().encode(folder.path).write(to: receipt, options: .atomic)
            }
            await kit.unloadModels()
            return segments
        } catch {
            await kit.unloadModels()
            throw error
        }
    }
}

actor SpeakerDiarizationEngine: DiarizationEngine {
    let models: URL
    init(models: URL) { self.models = models }
    func identifySpeakers(_ audio: URL, progress: @escaping EngineProgress) async throws -> [SpeakerTurn] {
        let diarizer = SpeakerKitDiarizer.pyannote(config: PyannoteConfig(downloadBase: models.path, verbose: false))
        let kit = try await SpeakerKit(PyannoteConfig(download: false, verbose: false, diarizer: diarizer))
        do {
            try await withModelDownloadProgress(message: "Downloading speaker models · 2 of 2", progress: progress) { callback in
                try await (diarizer as ModelManager).downloadModels(progressCallback: callback)
            }
            try Task.checkCancellation()
            await progress(ProcessingProgress(message: "Preparing speaker models for this Mac",
                detail: "Model files are on this Mac. First-time preparation can take several minutes. Speaker detection starts automatically."))
            try await diarizer.loadModels()
            try Task.checkCancellation()
            await progress(ProcessingProgress(message: "Listening for different speakers on your Mac",
                detail: "Your transcript is saved. Identifying speakers in the recording."))
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
            let result = try await kit.diarize(audioArray: samples)
            let turns = result.segments.compactMap { segment -> SpeakerTurn? in
                guard let id = segment.speaker.speakerId else { return nil }
                return SpeakerTurn(start: Double(segment.startTime), end: Double(segment.endTime), speakerID: id)
            }
            await kit.unloadModels()
            return turns
        } catch {
            await kit.unloadModels()
            throw error
        }
    }
}
