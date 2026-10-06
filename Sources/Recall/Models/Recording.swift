import Foundation
import Observation

enum ProcessingStatus: String, Codable, Sendable {
    case queued, transcribing, identifyingSpeakers, ready, failed
    var label: String {
        switch self {
        case .queued: "Queued"
        case .transcribing: "Transcribing"
        case .identifyingSpeakers: "Identifying speakers"
        case .ready: "Ready"
        case .failed: "Needs attention"
        }
    }
    var isProcessing: Bool { self == .transcribing || self == .identifyingSpeakers }
}

struct TranscriptWord: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
    var text: String
}

struct TranscriptSegment: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var speakerID: Int?
    var words: [TranscriptWord] = []
}

struct Speaker: Codable, Identifiable, Sendable, Equatable {
    var id: Int
    var name: String
}

enum SummaryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary = "Summary"
    case meetingMinutes = "Meeting Minutes"
    case decisions = "Decisions"
    case actionItems = "Action Items"
    case cleanNotes = "Clean Notes"
    var id: String { rawValue }
    var instruction: String {
        switch self {
        case .summary: "Write a concise overview of the main topics and outcomes."
        case .meetingMinutes: "Write structured meeting minutes with topics discussed, decisions, actions, and open questions."
        case .decisions: "Return only confirmed choices explicitly decided, agreed, selected, or approved. Statements such as I will do a task are action items, not decisions: exclude them. Example: We chose the blue design. I will email the mockup. The only decision is: Use the blue design. Apply this distinction to the actual source; never copy the example. If there are no explicit decisions, say so."
        case .actionItems: "Extract every concrete action from every speaker, including each I will commitment. Use one bullet per action: task; owner; deadline. Include an owner and deadline only when explicitly mentioned; otherwise mark them unspecified. Do not omit an action just because another speaker has already provided one. If there are no actions, say so."
        case .cleanNotes: "Turn dictated or informal speech into clean, organized notes. Preserve meaning, details, and qualifications."
        }
    }
}

struct GeneratedSummary: Codable, Identifiable, Sendable {
    var id = UUID()
    var kind: SummaryKind
    var text: String
    var createdAt = Date()
}

@Observable final class Recording: Codable, Identifiable {
    var id: UUID
    var originalFilename: String
    var audioFilename: String
    var contentHash: String
    var title: String
    var importedAt: Date
    var duration: Double
    var statusRaw: String
    var processingMessage: String?
    var failureMessage: String?
    var segments: [TranscriptSegment]
    var speakers: [Speaker]
    var summaries: [GeneratedSummary]
    var diarizationComplete: Bool

    init(id: UUID = UUID(), originalFilename: String, audioFilename: String,
         contentHash: String, duration: Double) {
        self.id = id
        self.originalFilename = originalFilename
        self.audioFilename = audioFilename
        self.contentHash = contentHash
        self.title = URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent
        self.importedAt = Date()
        self.duration = duration
        self.statusRaw = ProcessingStatus.queued.rawValue
        self.segments = []
        self.speakers = []
        self.summaries = []
        self.diarizationComplete = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalFilename, audioFilename, contentHash, title, importedAt, duration,
             statusRaw, processingMessage, failureMessage, segments, speakers, summaries, diarizationComplete
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        originalFilename = try c.decode(String.self, forKey: .originalFilename)
        audioFilename = try c.decode(String.self, forKey: .audioFilename)
        contentHash = try c.decode(String.self, forKey: .contentHash)
        title = try c.decode(String.self, forKey: .title)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        duration = try c.decode(Double.self, forKey: .duration)
        statusRaw = try c.decode(String.self, forKey: .statusRaw)
        processingMessage = try c.decodeIfPresent(String.self, forKey: .processingMessage)
        failureMessage = try c.decodeIfPresent(String.self, forKey: .failureMessage)
        segments = try c.decode([TranscriptSegment].self, forKey: .segments)
        speakers = try c.decode([Speaker].self, forKey: .speakers)
        summaries = try c.decode([GeneratedSummary].self, forKey: .summaries)
        diarizationComplete = try c.decode(Bool.self, forKey: .diarizationComplete)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(originalFilename, forKey: .originalFilename)
        try c.encode(audioFilename, forKey: .audioFilename)
        try c.encode(contentHash, forKey: .contentHash)
        try c.encode(title, forKey: .title)
        try c.encode(importedAt, forKey: .importedAt)
        try c.encode(duration, forKey: .duration)
        try c.encode(statusRaw, forKey: .statusRaw)
        try c.encodeIfPresent(processingMessage, forKey: .processingMessage)
        try c.encodeIfPresent(failureMessage, forKey: .failureMessage)
        try c.encode(segments, forKey: .segments)
        try c.encode(speakers, forKey: .speakers)
        try c.encode(summaries, forKey: .summaries)
        try c.encode(diarizationComplete, forKey: .diarizationComplete)
    }

    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }
    func speakerName(_ id: Int?) -> String {
        guard let id else { return "Unassigned speaker" }
        return speakers.first { $0.id == id }?.name ?? "Speaker \(id + 1)"
    }
    var transcript: String {
        segments.map { "\(speakerName($0.speakerID)) · \(TimeLabel.format($0.start))\n\($0.text)" }
            .joined(separator: "\n\n")
    }
    func renameSpeaker(_ id: Int, to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        var updated = speakers
        updated[index].name = cleaned
        speakers = updated
    }
}

enum TimeLabel {
    static func format(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
