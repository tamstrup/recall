import SwiftUI

struct ProcessingProgressView: View {
    let progress: ProcessingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(progress.message).font(.callout.weight(.medium)).lineLimit(2)
                Spacer(minLength: 8)
                if let download = progress.download, download.totalFiles > 0 {
                    Text("\(download.percent)%").font(.callout).monospacedDigit()
                        .accessibilityLabel("Model files \(download.percent) percent complete")
                }
            }
            if let download = progress.download, download.totalFiles > 0 {
                ProgressView(value: download.fraction).tint(.purple)
                    .accessibilityLabel("Model file download progress")
                HStack {
                    Text(download.fileLabel)
                    if download.fraction < 1, let speed = download.speedLabel {
                        Text("·")
                        Text(speed).monospacedDigit()
                    }
                    Spacer()
                    elapsed
                }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    elapsed
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let detail = progress.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var elapsed: some View {
        HStack(spacing: 3) {
            Text(progress.startedAt, style: .timer).monospacedDigit()
            Text("elapsed")
        }.fixedSize()
    }
}
