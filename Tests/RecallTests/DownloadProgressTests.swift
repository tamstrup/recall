import Foundation
import Testing
@testable import Recall

actor ProgressRecorder {
    var values: [ProcessingProgress] = []
    func append(_ value: ProcessingProgress) { values.append(value) }
}

struct DownloadProgressTests {
    @Test func includesPartialFileAndSnapshotsMutableProgress() {
        let parent = Progress(totalUnitCount: 2)
        let child = Progress(totalUnitCount: 100, parent: parent, pendingUnitCount: 1)
        child.completedUnitCount = 50
        parent.setUserInfoObject(1_000_000.0, forKey: .throughputKey)
        let snapshot = DownloadProgress(parent)
        child.completedUnitCount = 100
        #expect(snapshot.percent == 25)
        #expect(snapshot.completedFiles == 0)
        #expect(snapshot.totalFiles == 2)
        #expect(snapshot.bytesPerSecond == 1_000_000)
        #expect(snapshot.speedLabel != nil)
        #expect(DownloadProgress(parent).percent == 50)
    }

    @Test(arguments: [false, true])
    func finishesProgressBeforeReturningOrThrowing(fails: Bool) async throws {
        let recorder = ProgressRecorder()
        do {
            try await withModelDownloadProgress(message: "Downloading", progress: { await recorder.append($0) }) { callback in
                let value = Progress(totalUnitCount: 10)
                for completed in 0...10 {
                    value.completedUnitCount = Int64(completed)
                    callback(value)
                }
                if fails { throw RecallError(message: "Connection lost") }
            }
            #expect(!fails)
        } catch {
            #expect(fails)
            #expect(error.localizedDescription == "Connection lost")
        }
        await recorder.append("Preparing")
        let values = await recorder.values
        #expect(values.first?.message == "Downloading")
        #expect(values.dropLast().last?.download?.percent == 100)
        #expect(values.last?.message == "Preparing")
    }

    @Test func unknownTotalsAndInvalidSpeedDoNotInventEstimates() {
        let value = Progress(totalUnitCount: -1)
        value.setUserInfoObject(Double.nan, forKey: .throughputKey)
        let snapshot = DownloadProgress(value)
        #expect(snapshot.totalFiles == 0)
        #expect(snapshot.bytesPerSecond == nil)
        #expect(snapshot.speedLabel == nil)
    }
}
