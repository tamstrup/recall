# Recall icon

The current icon is the user-supplied **Recall-AppIcon-macOS.zip** design: sculpted lilac lips with a lighter lower lip on a dark rounded square (candidate 3, revision 2). It replaces the earlier waveform-and-transcript icon.

## Source and assets

- `Assets/IconSource/Recall.png`: supplied original 1254 × 1254 artwork, with transparency preserved.
- `Assets/IconSource/prompt.txt`: generation prompt supplied in the package.
- `Assets/Recall-1024.png`: supplied 1024 px master.
- `Assets/Recall.iconset/`: all ten macOS icon entries, 16–1024 pixels.
- `Assets/Assets.xcassets/AppIcon.appiconset/`: matching Xcode asset catalog.
- `Assets/Recall.icns`: packaged application icon, also used in the empty Inbox.

The supplied catalog, iconset, master, and `.icns` were copied unchanged. All package checksums, PNG dimensions and alpha channels were verified, and all ten embedded ICNS images matched the supplied PNGs. Earlier designs remain available in Git history.

## Regenerate

The package already contains production assets; an ordinary app build uses them directly. If new raster exports are needed, run from the repository root (this resamples the source and may not reproduce the package's exact export bytes):

```sh
swift Scripts/generate-icon.swift Assets
iconutil -c icns Assets/Recall.iconset -o Assets/Recall.icns
./Scripts/build-app.sh
```

The bundle references `Recall.icns` through `CFBundleIconFile` in `Assets/Info.plist`. Quit and reopen Recall after rebuilding to refresh its running Dock icon.
