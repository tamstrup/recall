# Recall icon

Three directions were considered:

1. **Conversation trace** — an open return loop around three short lines. Combines revisiting, voice becoming text, and a remembered fragment.
2. **Echo pair** — two offset conversation outlines. Simple, but too close to a generic messaging app and less clear at 16 px.
3. **Sound bookmark** — three waveform bars ending in a bookmark notch. Clear audio association, but busier and more like a recording tool.

Selected: **conversation trace**. A warm white mark on a muted deep teal macOS rounded square, with no gradients, gloss, text, or microphone. Small sizes retain the silhouette and three strokes. The matching empty-state mark is drawn natively in SwiftUI.

`Scripts/generate-icon.swift` is the editable vector master and reproducibly generates all ten macOS icon sizes. No manual image generation is needed.

```sh
swift Scripts/generate-icon.swift Assets
iconutil -c icns Assets/Recall.iconset -o Assets/Recall.icns
```

`Assets/Assets.xcassets/AppIcon.appiconset` is ready for Xcode. The command-line bundle uses `Assets/Recall.icns`.
