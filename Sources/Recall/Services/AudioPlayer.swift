import AVFoundation
import Observation

@MainActor @Observable final class AudioPlayer {
    private var player: AVAudioPlayer?
    @ObservationIgnored nonisolated(unsafe) private var ticker: Task<Void, Never>?
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var errorMessage: String?

    func load(_ url: URL) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
            errorMessage = nil
        } catch { errorMessage = "Audio could not be opened: \(error.localizedDescription)" }
    }
    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
            isPlaying = player.play()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self, let audio = self.player else { return }
                    self.currentTime = audio.currentTime
                    self.isPlaying = audio.isPlaying
                    if !audio.isPlaying { self.currentTime = audio.duration; return }
                }
            }
        }
    }
    func seek(_ time: Double) {
        let bounded = min(max(time, 0), duration)
        player?.currentTime = bounded
        currentTime = bounded
    }
    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
    }
    deinit { ticker?.cancel() }
}
