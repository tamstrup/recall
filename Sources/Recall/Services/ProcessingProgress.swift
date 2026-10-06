import Foundation

/// Live UI state only: never persist a stale percentage across launches.
struct ProcessingProgress: Sendable, ExpressibleByStringLiteral {
    var message: String
    var startedAt: Date = Date()
    var download: DownloadProgress?
    var detail: String?

    init(message: String, startedAt: Date = Date(), download: DownloadProgress? = nil, detail: String? = nil) {
        self.message = message
        self.startedAt = startedAt
        self.download = download
        self.detail = detail
    }

    init(stringLiteral value: String) { message = value }
}

struct DownloadProgress: Sendable {
    var fraction: Double
    var completedFiles: Int64
    var totalFiles: Int64
    var bytesPerSecond: Double?

    init(_ progress: Progress) {
        // Argmax weights each file equally; these units are NOT bytes. Snapshot
        // the mutable Foundation object inside the callback before crossing actors.
        fraction = progress.fractionCompleted.isFinite ? min(1, max(0, progress.fractionCompleted)) : 0
        totalFiles = max(0, progress.totalUnitCount)
        completedFiles = min(totalFiles, max(0, progress.completedUnitCount))
        let speed = progress.userInfo[.throughputKey] as? Double
        bytesPerSecond = speed.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    var percent: Int { Int(fraction * 100) }
    var fileLabel: String { "\(completedFiles) of \(totalFiles) files ready" }
    var speedLabel: String? {
        bytesPerSecond.map {
            ByteCountFormatter.string(fromByteCount: Int64(min($0, 1e15)), countStyle: .file) + "/s"
        }
    }
}

/// One ordered consumer prevents late callbacks from replacing a newer stage.
/// Buffer just the latest snapshot so a busy download cannot flood the UI.
func withModelDownloadProgress<T>(message: String, progress: @escaping EngineProgress,
    operation: (@escaping @Sendable (Progress) -> Void) async throws -> T) async throws -> T {
    let startedAt = Date()
    let detail = "Models download once and stay on this Mac."
    await progress(ProcessingProgress(message: message, startedAt: startedAt, detail: detail))
    let (stream, continuation) = AsyncStream<DownloadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let consumer = Task {
        for await snapshot in stream {
            await progress(ProcessingProgress(message: message, startedAt: startedAt,
                download: snapshot, detail: detail))
        }
    }
    do {
        let result = try await operation { continuation.yield(DownloadProgress($0)) }
        continuation.finish()
        await consumer.value
        return result
    } catch {
        continuation.finish()
        await consumer.value
        throw error
    }
}
