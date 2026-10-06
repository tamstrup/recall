import Foundation
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
        await progress("Preparing transcription model · first use downloads the model")
        let receipt = models.appendingPathComponent("recall-whisper-\(modelName).json")
        let cachedFolder = (try? Data(contentsOf: receipt)).flatMap { try? JSONDecoder().decode(String.self, from: $0) }
        let localFolder = cachedFolder.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        let kit = try await WhisperKit(WhisperKitConfig(model: modelName, downloadBase: models,
            modelFolder: localFolder, verbose: false, prewarm: true, load: true, download: localFolder == nil))
        do {
            await progress("Transcribing on your Mac")
            let results = try await kit.transcribe(
                audioPath: audio.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                decodeOptions: DecodingOptions(verbose: false, wordTimestamps: true)
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
        await progress("Preparing speaker models · first use downloads the models")
        let kit = try await SpeakerKit(PyannoteConfig(downloadBase: models.path, verbose: false))
        do {
            await progress("Listening for different speakers on your Mac")
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
