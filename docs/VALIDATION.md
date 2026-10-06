# Validation

Verified on this Apple Silicon Mac, macOS 27.0, using Swift 6.4 and the installed macOS 26.5 SDK.

## Automated checks

All **15 tests** passed, including three opt-in checks against real decoders/models:

- Finder `NSItemProvider` file-URL decoding and multi-file import through the same path used by SwiftUI's drop handler.
- Identical-file deduplication, invalid-file rejection, and playback seeking.
- Core Data persistence round trip with segments, speakers, and summaries.
- Recovery of interrupted processing and continuation after a failed recording.
- Diarization failure preserves the transcript; retry skips successful transcription.
- Speaker renaming changes every occurrence and the summary input.
- Failed regeneration preserves an existing summary.
- Word-level speaker changes, unmatched speech, Unicode chunking, and timestamps.
- Digital silence fails before model download instead of producing a hallucinated transcript.
- Real WAV, AAC/M4A, and MP3 import via AVFoundation.
- A 39-second, two-voice synthetic recording was transcribed using the production Whisper model and diarized using SpeakerKit. Five Whisper segments aligned to **two speakers**. With prepared models, the entire speech test completed in about 10 seconds on this machine.
- Apple's on-device model generated all five formats. The Action Items check retained both named owners; the Decisions check retained the release decision and excluded a separate Thursday task.

The initial speech fixture was silent because sandboxed `say` could not access its voices. The test correctly failed; the fixture generator now checks that speech is present. Testing exposed both that silence edge case and omitted summary owners; the implementation and prompts were updated before the passing run.

Run regular tests:

```sh
./Scripts/swift.sh test --enable-swift-testing
```

Run the opt-in decoder and local-model checks (downloads models on first use; requires installed Samantha and Daniel voices and network access for the public silent MP3 fixture):

```sh
./Scripts/test-local-models.sh
```

The MP3 decoder fixture is one second of silence from [anars/blank-audio](https://github.com/anars/blank-audio). It is downloaded into ignored build files, not distributed with the application.

## Native UI checks

Launched the packaged application and captured its actual SwiftUI/AppKit content view with an isolated preview library. Inspected empty Inbox, recording/transcript, light and dark appearance, and Notes at the minimum supported window size. Images are in `docs/screenshots/`; sample conversation text is synthetic. The Inbox and dark recording captures include the native titlebar and toolbar; earlier recording and Notes captures show only the content view.

The drop provider and import pipeline are automated and verified. An actual mouse drag from Finder has not been driven by automation; that physical gesture and audio quality on the user's own recordings remain the short acceptance check in `TODO_USER.md`.

## Build

Debug and optimized release builds use `Scripts/build-app.sh`; the app is locally signed and has a complete `.icns` icon. App source compiles without warnings. Apple's Swift build driver emits harmless missing search-directory warnings for two Xcode-style paths absent from this Command Line Tools installation. The script selects the compatible installed SDK and explicitly supplies the Testing macro plugin path.

This is a functional MVP, not a benchmark of diarization accuracy or a guarantee of LLM factual completeness. No physical recorder or user-provided audio was available. Very long recordings and all supported macOS versions have not been exhaustively tested.

## Approved icon update

Replaced the original teal mark with the user-approved purple voice-to-text artwork. Verified all ten catalog/iconset PNG entries have their required pixel dimensions and RGBA transparency, and that the saved original matches the approved generated image byte for byte. Inspected the 128 px icon and refreshed the native Inbox screenshot. Rebuilt debug and release bundles and reran the 12 core tests successfully; the three opt-in decoder/model tests were skipped for this asset-only update (their earlier passing evidence is above).

## Header alignment fix (0.1.1)

Reproduced the titlebar separator extending into the sidebar: the native titlebar background began at x=278 while the detail column began at x=281. Hid the automatic toolbar material so each split column supplies its own aligned background, and configured the public `NSWindow.titlebarSeparatorStyle` to `.none` to remove the overhanging line. The native title and toolbar controls remain, without fixed padding or private-view changes. The preview helper now captures the complete window so titlebar regressions remain visible. Inspected the empty Inbox in light mode and a recording in dark mode at the minimum window size. Debug/release builds and local signing verification passed. The transfer ZIP was refreshed for this patch.

## Model download progress (0.1.2)

Download callbacks now drive a progress bar, percentage across files, completed file count, optional transfer speed, and elapsed time. Preparation has a separate message and elapsed timer. Argmax 1.1.0's Hub snapshot progress weights files equally; it does not expose aggregate bytes or a reliable ETA. Short downloads may not produce any speed sample. The UI does not invent these values.

Verified first-run downloads in a separate, empty `.build/progress-test-models` cache: Whisper reported 82 progress updates across 17 files; SpeakerKit reported 27 across 23 files. Both reported partial progress and reached 100% before inference. The real recording produced five transcript segments and two speakers. The final suite passed all 16 regular tests plus the real speech pipeline and audio-format import tests; the unrelated opt-in Apple summary test was skipped. The cached speech pipeline took about seven seconds.

New checks cover partial-file percentages, immutable callback snapshots, unknown totals, invalid/absent speed, and draining progress updates before success or failure so late callbacks cannot overwrite a newer stage. A disk-backed recovery test confirms that reopening interrupted speaker detection retains the saved transcript, skips retranscription, and discards stale progress. Progress details remain transient and require no library migration.

Inspected native download and preparation panels in light/dark mode at the minimum window size. Bounded multiline labels prevent SwiftUI's split-view minimum-size measurement from expanding the content beyond the window. The captures in `docs/screenshots/model-download.png` and `model-preparation-dark.png` use synthetic progress and an isolated preview library.

Built the optimized ARM64 app as version 0.1.2 (build 3), verified its local code signature, and validated `build/Recall-0.1.2-macOS-arm64.zip` with `unzip -t`. The unversioned transfer ZIP contains the same release. Model weights remain separate and download on each Mac's first use.
