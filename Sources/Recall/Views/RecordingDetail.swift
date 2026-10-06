import SwiftUI
import AppKit

struct RecordingDetail: View {
    @Environment(RecallStore.self) private var store
    @Bindable var recording: Recording
    @State private var player = AudioPlayer()
    @State private var tab = DetailTab.transcript
    @State private var speakerToRename: Speaker?
    @State private var editedName = ""
    @State private var summaryKind = SummaryKind.summary
    @State private var summaryUnavailable = SummaryAvailability.unavailableReason
    private enum DetailTab: String, CaseIterable { case transcript = "Transcript", notes = "Notes" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            playerControls.padding(.horizontal, 32).padding(.vertical, 20)
            if let message = recording.failureMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recording.segments.isEmpty ? "Processing couldn’t finish" : "Your transcript is saved")
                            .fontWeight(.medium)
                        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button(recording.segments.isEmpty ? "Retry" : "Retry Speakers") { store.retry(recording) }
                }.font(.callout).padding(.horizontal, 32).padding(.bottom, 20)
            }
            if recording.status.isProcessing || recording.status == .queued {
                if let progress = recording.processingProgress {
                    ProcessingProgressView(progress: progress)
                        .padding(.horizontal, 32).padding(.bottom, 18)
                } else {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(recording.processingMessage ?? recording.status.label).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.horizontal, 32).padding(.bottom, 18)
                }
            }
            HStack {
                Picker("View", selection: $tab) {
                    ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                if tab == .transcript, !recording.segments.isEmpty {
                    Button { copy(recording.transcript) } label: { Label("Copy Transcript", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
            }.padding(.horizontal, 32).padding(.bottom, 16)
            Divider()
            if tab == .transcript { transcriptView } else { summaryView }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(recording.title)
        .onAppear {
            player.load(store.library.url(for: recording.audioFilename))
            #if DEBUG
            if ProcessInfo.processInfo.environment["RECALL_NOTES_UI"] == "1" { tab = .notes }
            #endif
        }
        .onDisappear { player.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            summaryUnavailable = SummaryAvailability.unavailableReason
        }
        .sheet(item: $speakerToRename) { speaker in
            VStack(alignment: .leading, spacing: 18) {
                Text("Rename speaker").font(.title3.bold())
                Text("This name applies throughout this recording.").foregroundStyle(.secondary)
                TextField("Name", text: $editedName).textFieldStyle(.roundedBorder)
                    .onSubmit { rename(speaker) }
                HStack {
                    Spacer()
                    Button("Cancel") { speakerToRename = nil }.keyboardShortcut(.cancelAction)
                    Button("Save") { rename(speaker) }.keyboardShortcut(.defaultAction)
                        .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 340)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Recording title", text: $recording.title)
                .textFieldStyle(.plain).font(.system(size: 25, weight: .semibold))
                .onSubmit { store.save() }
                .onChange(of: recording.title) { _, _ in store.save() }
                .accessibilityLabel("Recording title")
            HStack(spacing: 7) {
                Text(recording.importedAt, format: .dateTime.day().month(.wide).year())
                Text("·")
                Text(TimeLabel.format(recording.duration))
                if !recording.speakers.isEmpty {
                    Text("·")
                    Text("\(recording.speakers.count) \(recording.speakers.count == 1 ? "speaker" : "speakers")")
                }
                Spacer()
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(32)
    }

    private var playerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17)).frame(width: 38, height: 38)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .disabled(player.errorMessage != nil)
                Text(TimeLabel.format(player.currentTime)).monospacedDigit().font(.caption)
                    .foregroundStyle(.secondary).frame(minWidth: 35)
                Slider(value: Binding(get: { player.currentTime }, set: player.seek), in: 0...max(player.duration, 0.01))
                    .accessibilityLabel("Playback position").disabled(player.errorMessage != nil)
                Text(TimeLabel.format(player.duration)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
            }
            if let error = player.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var transcriptView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                if recording.segments.isEmpty {
                    Text(recording.status == .failed ? "The transcript will appear here after processing succeeds." : "Your transcript will appear here.")
                        .foregroundStyle(.secondary).padding(.top, 24)
                }
                ForEach(recording.segments) { segment in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 9) {
                            Circle().fill(speakerColor(segment.speakerID)).frame(width: 6, height: 6)
                            if let id = segment.speakerID, let speaker = recording.speakers.first(where: { $0.id == id }) {
                                Button {
                                    editedName = speaker.name
                                    speakerToRename = speaker
                                } label: {
                                    Text(speaker.name).fontWeight(.semibold)
                                }.buttonStyle(.plain).help("Rename \(speaker.name)")
                            } else { Text(recording.speakerName(segment.speakerID)).foregroundStyle(.secondary) }
                            Button { player.seek(segment.start) } label: {
                                Text(TimeLabel.format(segment.start)).monospacedDigit().foregroundStyle(.secondary)
                            }.buttonStyle(.plain).help("Play from \(TimeLabel.format(segment.start))")
                            Spacer()
                        }.font(.caption)
                        Text(segment.text).font(.system(size: 15)).lineSpacing(5)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle()).onTapGesture { player.seek(segment.start) }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        if player.isPlaying, player.currentTime >= segment.start, player.currentTime < segment.end {
                            Rectangle().fill(Color.accentColor).frame(width: 2)
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Picker("Create", selection: $summaryKind) {
                        ForEach(SummaryKind.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 175)
                    Spacer()
                    if store.summarizingIDs.contains(recording.id) {
                        ProgressView().controlSize(.small)
                        Text("Writing on your Mac…").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Button(recording.summaries.contains(where: { $0.kind == summaryKind }) ? "Regenerate" : "Generate") {
                            let kind = summaryKind
                            Task { await store.generateSummary(for: recording, kind: kind) }
                        }.disabled(recording.segments.isEmpty || summaryUnavailable != nil)
                    }
                }
                if let reason = summaryUnavailable {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        Button("Check Availability") { summaryUnavailable = SummaryAvailability.unavailableReason }
                            .buttonStyle(.borderless)
                    }
                }
                if let summary = recording.summaries.first(where: { $0.kind == summaryKind }) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(summary.kind.rawValue).font(.title3.weight(.semibold))
                            Spacer()
                            Button { copy(summary.text) } label: { Label("Copy", systemImage: "doc.on.doc") }
                                .buttonStyle(.borderless)
                        }
                        // Render paragraphs independently to retain readable Markdown line breaks.
                        ForEach(Array(summary.text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            if line.isEmpty { Spacer().frame(height: 2) }
                            else { Text(.init(line)).textSelection(.enabled).font(.system(size: 15)).lineSpacing(5) }
                        }
                        Text("Generated on this Mac · Check important details against the recording.")
                            .font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make something useful.").font(.title3.weight(.medium))
                        Text("Choose a format to turn this conversation into an overview, meeting minutes, or your next steps.")
                            .foregroundStyle(.secondary).lineSpacing(4)
                        Text("Only generated when you ask. Always on this Mac.").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.top, 20)
                }
            }.padding(32).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rename(_ speaker: Speaker) {
        recording.renameSpeaker(speaker.id, to: editedName)
        store.save()
        speakerToRename = nil
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    private func speakerColor(_ id: Int?) -> Color {
        guard let id else { return .secondary }
        let colors: [Color] = [.teal, .indigo, .orange, .purple, .blue, .pink]
        return colors[abs(id) % colors.count]
    }
}
