import AppKit
import UniformTypeIdentifiers

// Finder advertises file URLs. Keep decoding here shared by the UI and tests.
enum AudioDrop {
    static func urls(from providers: [NSItemProvider]) async throws -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: error ?? RecallError(message: "The dropped file could not be read.")) }
                }
            }
            guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                throw RecallError(message: "Drop audio files from Finder into Recall.")
            }
            urls.append(url)
        }
        return urls
    }
}
