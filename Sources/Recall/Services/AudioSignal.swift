import AVFoundation

// Reject digital silence before Whisper can hallucinate a closing phrase. This
// is not speech detection: quiet speech and noisy recordings still reach Whisper.
// Reads bounded buffers and stops at the first audible sample.
enum AudioSignal {
    static func hasAudibleSamples(_ url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return false }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) where abs(channels[channel][frame]) > 0.00001 { return true }
            }
        }
        return false
    }
}
