import AVFoundation
import CryptoKit
import Foundation

struct ImportedAudio: Sendable {
    let id: UUID
    let originalFilename: String
    let audioFilename: String
    let contentHash: String
    let duration: Double
}

actor AudioLibrary {
    nonisolated let root: URL
    init(root: URL) { self.root = root }
    nonisolated func url(for filename: String) -> URL { root.appendingPathComponent(filename) }

    func importFile(_ source: URL, existingHashes: Set<String> = []) async throws -> ImportedAudio {
        guard source.isFileURL else { throw RecallError(message: "Choose an audio file on your Mac.") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw RecallError(message: "Folders cannot be imported. Choose audio files instead.") }
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        guard !tracks.isEmpty, duration.isFinite, duration > 0 else {
            throw RecallError(message: "This file does not contain playable audio.")
        }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let filename = id.uuidString + "." + source.pathExtension.lowercased()
        let destination = url(for: filename)
        do {
            // Skip the managed copy entirely when the library already owns these bytes.
            if !existingHashes.contains(hash) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return ImportedAudio(id: id, originalFilename: source.lastPathComponent, audioFilename: filename,
                             contentHash: hash, duration: duration)
    }
    func remove(_ filename: String) throws {
        let file = url(for: filename)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
