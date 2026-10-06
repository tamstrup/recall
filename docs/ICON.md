# Recall icon

The approved **voice into text** mark combines rounded waveform bars with three transcript lines. A violet-to-plum gradient and softly raised pale lilac forms give it depth while keeping a clear silhouette. It replaces the original flat teal conversation-trace direction.

## Source and assets

- `Assets/IconSource/Recall.png`: original approved 1254 × 1254 artwork, generated with the built-in image-generation tool, with transparency preserved.
- `Assets/IconSource/prompt.txt`: exact generation prompt and provenance.
- `Assets/Recall-1024.png`: resampled 1024 px master.
- `Assets/Recall.iconset/`: all ten macOS icon entries, 16–1024 pixels.
- `Assets/Assets.xcassets/AppIcon.appiconset/`: matching Xcode asset catalog.
- `Assets/Recall.icns`: packaged application icon, also used in the empty Inbox.

The source is raster artwork. The asset script preserves the approved design, alpha channel, and full composition, using high-quality resampling into sRGB. It does not invoke image generation or need credentials. The original design remains available in Git history.

## Regenerate

Run from the repository root:

```sh
swift Scripts/generate-icon.swift Assets
iconutil -c icns Assets/Recall.iconset -o Assets/Recall.icns
./Scripts/build-app.sh
```

The bundle references `Recall.icns` through `CFBundleIconFile` in `Assets/Info.plist`. Quit and reopen Recall after rebuilding to refresh its running Dock icon.
