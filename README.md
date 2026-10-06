# Recall

A small, native Mac utility for returning to recorded conversations. Import audio, read a speaker-separated transcript, listen back, rename speakers, and generate notes. Audio and transcripts stay on your Mac. No accounts, analytics, cloud inference, or microphone permission.

## Build and run

Apple Silicon, macOS 14+, and a Swift 6 toolchain with the macOS 26 SDK or newer. Summaries require macOS 26+ with Apple Intelligence enabled and its model ready.

```sh
./Scripts/build-app.sh
open build/Recall.app
```

The script builds a release executable, bundles the icon and license notices, and signs the app locally. For development, use `./Scripts/build-app.sh debug`. Open `Package.swift` in Xcode if preferred. No signing account is needed for local use. The script handles this machine's Command Line Tools setup by selecting the installed 26.5 SDK; its 27 SDK lacks the SwiftUI macro plugin. Full Xcode uses its selected SDK normally.

```sh
./Scripts/swift.sh test --enable-swift-testing
```

## Use

Drop one or more files anywhere in the window, or use **⌘O**. WAV, M4A, MP3, and other AVFoundation audio formats are supported. Imports are copied once into Recall's library; repeated identical files select the existing recording. Originals are never moved or modified.

The queue transcribes and identifies speakers one recording at a time. Open a recording to play/pause or scrub. Click transcript text or a timestamp to seek, and click a speaker's name to rename them throughout that recording. In **Notes**, choose Summary, Meeting Minutes, Decisions, Action Items, or Clean Notes, then Generate. Transcript and notes can be copied.

Recall detects the spoken language and transcribes in that language. For recordings processed by an earlier version with incorrect language detection, open the **…** menu beside the title and choose **Transcribe Again…**. The existing transcript, speaker names, and notes remain until the new transcription succeeds; successful retranscription replaces them. A failed attempt can be retried.

Use **Delete Recording…** in the same menu, or right-click a recording in the sidebar. Confirming removes Recall's managed audio copy, transcript, and notes; it never deletes the original imported file. Deleting an active recording cancels its processing and lets the remaining queue continue after the current model operation returns.

Failed speaker detection preserves the transcript. Retry resumes the missing stage. Quitting stops processing; reopening automatically retries unfinished recordings. An interrupted transcription restarts from the beginning because partial transcripts are not saved. If transcription finished and was saved, recovery starts with speaker detection. Imported audio and completed results remain in the library. Failed summary regeneration preserves the previous result.

## Models and storage

First import automatically downloads Whisper `large-v3-v20240930_626MB` and SpeakerKit's default Pyannote models from Hugging Face. Each download shows a progress bar, percentage across model files, completed file count, download speed when available, and elapsed time. The SDK weights files equally, so this is file progress, not a byte percentage or time estimate. Model preparation is a separate stage: the files are already on the Mac, and first-time preparation can take several minutes. Preparation and other stages without a measurable percentage show an animated bar, an explicit percentage-unavailable label, and elapsed time. Allow several GB of free space for downloads, compiled models, and audio. No Hugging Face account or API key is required. Subsequent processing uses local models. Foundation Models is supplied and downloaded by macOS itself.

Library: `~/Library/Application Support/Recall/`

- `Recall.sqlite` and SQLite sidecars: recording metadata and results.
- `Audio/`: one managed copy per imported recording.
- `Models/`: downloadable speech models and tokenizer cache.

Back up the complete library while Recall is closed. Audio is not embedded in the database. No network API accepts user audio or transcript content.

## Structure

SwiftUI views → main-actor `RecallStore` → three small engine protocols. WhisperKit transcription and SpeakerKit diarization run in service actors; AVFoundation handles decoding/playback. Word timestamps align speech to speaker turns. Apple Foundation Models generates summaries, using fresh sessions and bounded chunk reduction for long transcripts.

A small programmatic Core Data SQLite store persists Codable recordings. Core Data was chosen because this environment has no SwiftData compiler plugin; it retains native transactional persistence without requiring an Xcode installation. Models and audio stay separate from UI state.

## Dependencies and licenses

- [Argmax OSS Swift 1.1.0](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.0): WhisperKit, SpeakerKit, ArgmaxCore — MIT.
- Vendored Hugging Face swift-transformers in ArgmaxCore — Apache 2.0.
- Swift Argument Parser (Argmax's package dependency; CLI not used by Recall) — Apache 2.0.
- [WhisperKit Core ML weights](https://huggingface.co/argmaxinc/whisperkit-coreml) — MIT.
- [SpeakerKit Core ML weights](https://huggingface.co/argmaxinc/speakerkit-coreml) — CC BY 4.0; Argmax/Pyannote attribution in `Assets/Licenses`.
- SwiftUI, Core Data, AVFoundation, Foundation Models — Apple system frameworks.

Exact package revisions are in `Package.resolved`. Notices ship inside the app. API choices were checked against the pinned source and [Apple's Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

## Current limitations

Speaker separation and transcription are estimates, particularly with overlapping speech, noise, and very short clips. Speaker identities are specific to each recording. Diarization decodes the recording into memory; very long recordings can require substantial RAM. Transcription uses incremental audio loading. Model preparation shows a stage indicator rather than a percentage.

Apple summaries are unavailable on unsupported Macs or while Apple Intelligence is disabled/downloading. There is no cloud fallback. Long recordings use lossy chunk reduction; check important names, decisions, and deadlines against the audio. Existing notes are snapshots: regenerate after renaming speakers if you want updated names.

This is a locally signed development app, not a notarized distribution. No live recording, search, projects, or cloud sync is included. See `TODO_USER.md` for any checks that still need you, and `docs/VALIDATION.md` for verification evidence.

## Icon and UI previews

The approved purple voice-to-text icon uses a shaded waveform flowing into transcript lines. Its original artwork and image-generation prompt are saved in `Assets/IconSource/`. `Scripts/generate-icon.swift` resamples that artwork into a complete macOS asset catalog, iconset, 1024 px master, and `.icns` (using `iconutil`). The Inbox uses the same bundled icon. See `docs/ICON.md` for regeneration instructions. Screenshots under `docs/screenshots/` are native SwiftUI captures using isolated synthetic sample data.
