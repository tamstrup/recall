import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct InboxView: View {
    @Environment(RecallStore.self) private var store
    private var recordings: [Recording] { store.recordings }
    @State private var dropTargeted = false
    @State private var recordingToDelete: Recording?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            Group {
                if recordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray").font(.system(size: 29, weight: .light)).foregroundStyle(.secondary)
                        Text("Your recordings").font(.headline)
                        Text("Everything you import\nappears here.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $store.selectedID) {
                        ForEach(recordings) { recording in
                            RecordingRow(recording: recording).tag(recording.id)
                                .contextMenu {
                                    Button("Delete Recording…", role: .destructive) { recordingToDelete = recording }
                                }
                        }
                    }.listStyle(.sidebar)
                }
            }
            .navigationTitle("Inbox")
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 7) {
                    Image(systemName: "lock").font(.caption)
                    Text("Kept on this Mac").font(.caption)
                    Spacer()
                    if store.importingCount > 0 { ProgressView().controlSize(.mini) }
                }.foregroundStyle(.secondary).padding(16)
            }
            .toolbar {
                ToolbarItem {
                    Button(action: store.showImporter) { Label("Import Recordings", systemImage: "plus") }
                        .help("Import recordings (⌘O)")
                }
            }
        } detail: {
            if let recording = recordings.first(where: { $0.id == store.selectedID }) {
                RecordingDetail(recording: recording).id(recording.id)
            } else {
                VStack(spacing: 18) {
                    RecallLogo()
                        .frame(width: 72, height: 72).padding(.bottom, 8)
                    Text(recordings.isEmpty ? "Drop recordings here" : "Choose a recording")
                        .font(.system(size: 23, weight: .medium))
                    Text(recordings.isEmpty ? "A place to return to what was said." : "Listen, read, and make something useful.")
                        .foregroundStyle(.secondary)
                    Button("Import Recordings…", action: store.showImporter).controlSize(.large).padding(.top, 6)
                    Text("WAV, M4A, MP3, and more").font(.caption).foregroundStyle(.tertiary)
                    if recordings.isEmpty {
                        Text("Speech models download on first use.\nYour audio stays on your Mac.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 25)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .navigationTitle("Recall")
            }
        }
        // Let each split column's background extend through the titlebar. The
        // system toolbar material otherwise overhangs the sidebar divider.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay {
            if dropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.07)
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
                        .padding(10)
                    Label("Drop to import", systemImage: "arrow.down.doc")
                        .font(.title3).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }.allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            guard !providers.isEmpty else { return false }
            Task {
                do { await store.importFiles(try await AudioDrop.urls(from: providers)) }
                catch { store.alertMessage = error.localizedDescription }
            }
            return true
        }
        .confirmationDialog("Delete this recording?", isPresented: Binding(
            get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }
        ), titleVisibility: .visible, presenting: recordingToDelete) { recording in
            Button("Delete Recording", role: .destructive) { Task { await store.delete(recording) } }
        } message: { _ in
            Text("This deletes Recall’s copy of the audio, transcript, and notes. Your original file is unchanged.")
        }
        .alert("Recall couldn’t finish that", isPresented: Binding(
            get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK") { store.alertMessage = nil }
        } message: { Text(store.alertMessage ?? "") }
        .frame(minWidth: 800, minHeight: 540)
    }
}

struct RecordingRow: View {
    let recording: Recording
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(recording.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
            HStack(spacing: 5) {
                Text(recording.importedAt, format: .dateTime.month(.abbreviated).day())
                Text("·")
                Text(TimeLabel.format(recording.duration))
            }.font(.caption).foregroundStyle(.secondary)
            if recording.status != .ready {
                HStack(spacing: 5) {
                    if recording.status.isProcessing { ProgressView().controlSize(.mini) }
                    else { Image(systemName: recording.status == .failed ? "exclamationmark.circle" : "clock") }
                    Text(recording.status.label)
                }.font(.caption).foregroundStyle(recording.status == .failed ? Color.orange : Color.secondary)
            }
        }.padding(.vertical, 9)
    }
}

struct RecallLogo: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "Recall", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                .accessibilityHidden(true)
        } else {
            // A bare `swift run` executable has no app bundle resources.
            Image(systemName: "waveform").resizable().scaledToFit()
                .foregroundStyle(.purple).accessibilityHidden(true)
        }
    }
}
