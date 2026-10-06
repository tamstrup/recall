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
            guard start.isFinite, end.isFinite, end >= start else { return nil }
            if start < previousStart { cursor = 0 }
            previousStart = start
            while cursor < orderedTurns.count, orderedTurns[cursor].end <= start { cursor += 1 }
            var candidate = cursor
            var bestOverlap = 0.0
            var best: Int?
            // Whisper can give punctuation and short words zero-duration timestamps.
            // Such a word still belongs to a turn containing its timestamp.
            if end == start, let turn = orderedTurns.dropFirst(cursor).prefix(while: { $0.start <= start }).first(where: { $0.end > start }) {
                return turn.speakerID
            }
            while candidate < orderedTurns.count, orderedTurns[candidate].start < end {
                let turn = orderedTurns[candidate]
                let overlap = max(0, min(end, turn.end) - max(start, turn.start))
                if overlap > bestOverlap { bestOverlap = overlap; best = turn.speakerID }
                candidate += 1
            }
            if let best { return best }
            // Bridge only a short gap bounded by the SAME speaker. Do not guess
            // across speaker changes or genuinely uncovered stretches of audio.
            if cursor > 0, cursor < orderedTurns.count {
                let before = orderedTurns[cursor - 1]
                let after = orderedTurns[cursor]
                if before.speakerID == after.speakerID,
                   before.end <= start, after.start >= end,
                   after.start - before.end <= 0.6 {
                    return before.speakerID
                }
            }
            return nil
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
        let normalized = result.map { segment in
            var copy = segment
            if let id = segment.speakerID {
                if mapping[id] == nil { mapping[id] = mapping.count }
                copy.speakerID = mapping[id]
            }
            return copy
        }
        var paragraphs: [TranscriptSegment] = []
        for segment in normalized {
            if let last = paragraphs.indices.last,
               paragraphs[last].speakerID == segment.speakerID,
               segment.start >= paragraphs[last].start,
               segment.start - paragraphs[last].end <= 1.5,
               paragraphs[last].text.count + segment.text.count < 600 {
                paragraphs[last].text += " " + segment.text
                paragraphs[last].end = max(paragraphs[last].end, segment.end)
                paragraphs[last].words += segment.words
            } else { paragraphs.append(segment) }
        }
        return paragraphs
    }
}
