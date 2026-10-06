import Foundation

typealias EngineProgress = @Sendable (ProcessingProgress) async -> Void

protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: URL, progress: @escaping EngineProgress) async throws -> [TranscriptSegment]
}
protocol DiarizationEngine: Sendable {
    func identifySpeakers(_ audio: URL, progress: @escaping EngineProgress) async throws -> [SpeakerTurn]
}
protocol SummaryEngine: Sendable {
    func summarize(_ transcript: String, kind: SummaryKind) async throws -> String
}

struct SpeakerTurn: Sendable {
    var start: Double
    var end: Double
    var speakerID: Int
}

struct RecallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Use word timestamps when available so a speaker change inside a Whisper segment
// creates two conversational blocks. Never invent a speaker for uncovered speech.
enum SpeakerAlignment {
    static func align(_ segments: [TranscriptSegment], turns: [SpeakerTurn]) -> [TranscriptSegment] {
        let orderedTurns = turns.sorted { $0.start < $1.start }
        var cursor = 0
        var previousStart = -Double.infinity
        func speaker(start: Double, end: Double) -> Int? {
            if start < previousStart { cursor = 0 }
            previousStart = start
            while cursor < orderedTurns.count, orderedTurns[cursor].end <= start { cursor += 1 }
            var candidate = cursor
            var bestOverlap = 0.0
            var best: Int?
            while candidate < orderedTurns.count, orderedTurns[candidate].start < end {
                let turn = orderedTurns[candidate]
                let overlap = max(0, min(end, turn.end) - max(start, turn.start))
                if overlap > bestOverlap { bestOverlap = overlap; best = turn.speakerID }
                candidate += 1
            }
            return best
        }
        var result: [TranscriptSegment] = []
        for segment in segments {
            if segment.words.isEmpty {
                var copy = segment
                copy.speakerID = speaker(start: segment.start, end: segment.end)
                result.append(copy)
                continue
            }
            var groups: [TranscriptSegment] = []
            for word in segment.words {
                let id = speaker(start: word.start, end: word.end)
                if let last = groups.indices.last, groups[last].speakerID == id {
                    groups[last].text += word.text
                    groups[last].end = word.end
                    groups[last].words.append(word)
                } else {
                    groups.append(TranscriptSegment(start: word.start, end: word.end, text: word.text,
                                                    speakerID: id, words: [word]))
                }
            }
            result += groups.map {
                var copy = $0
                copy.text = copy.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }.filter { !$0.text.isEmpty }
        }
        // Normalize arbitrary cluster IDs to stable, human-friendly order of appearance.
        var mapping: [Int: Int] = [:]
        return result.map { segment in
            var copy = segment
            if let id = segment.speakerID {
                if mapping[id] == nil { mapping[id] = mapping.count }
                copy.speakerID = mapping[id]
            }
            return copy
        }
    }
}
