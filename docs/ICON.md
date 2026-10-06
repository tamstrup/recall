# Recall icon

The current icon is the user-supplied **Recall-AppIcon-macOS.zip** design: sculpted lilac lips with a lighter lower lip on a dark rounded square (candidate 3, revision 2). It replaces the earlier waveform-and-transcript icon.

## Source and assets

- `Assets/IconSource/Recall.png`: supplied original 1254 × 1254 artwork, with transparency preserved.
- `Assets/IconSource/prompt.txt`: generation prompt supplied in the package.
- `Assets/Recall-1024.png`: supplied 1024 px master.
- `Assets/Recall.iconset/`: all ten macOS icon entries, 16–1024 pixels.
- `Assets/Assets.xcassets/AppIcon.appiconset/`: matching Xcode asset catalog.
- `Assets/Recall.icns`: legacy fallback, also used in the empty Inbox.
- `Assets/Recall.icon/`: modern Icon Composer source. Its `Artwork.png` is byte-identical to the supplied 1024 px master.
- `Assets/CompiledIcon/`: Xcode-compiled `Assets.car`, compiler metadata, and a SHA-256 manifest linking the catalog to its source.

The supplied catalog, iconset, master, and `.icns` were copied unchanged. All package checksums, PNG dimensions and alpha channels were verified, and all ten embedded ICNS images matched the supplied PNGs. Earlier designs remain available in Git history.

## Modern macOS presentation

Recent macOS versions presented the legacy-only icon inside an additional silver rounded square. The app now includes the Icon Composer catalog and declares `CFBundleIconName = Recall`, while retaining `CFBundleIconFile = Recall` for compatibility. The composition uses the approved artwork on a matching dark background, at 1.08 scale to fill the system enclosure. Extra glass, shadow, and specular effects are disabled because the artwork is already shaded. The PNG itself is unchanged.

Ordinary builds verify the source/catalog hashes and copy the checked-in catalog into the app. They do not require full Xcode. Before/after captures from macOS's `NSWorkspace` icon service are in `docs/screenshots/icon-system-before.png` and `icon-system-after.png`.

## Regenerate the modern catalog

After editing `Assets/Recall.icon` with Icon Composer, run with Xcode 26+ selected:

```sh
zsh Scripts/compile-icon.sh
./Scripts/build-app.sh
```

Alternatively, push the source change or manually run the **Compile macOS icon** GitHub Actions workflow. Download its `recall-native-icon` artifact and copy the enclosed `CompiledIcon/` directory to `Assets/CompiledIcon/`. Inspect the included Default/Dark previews, run `python3 Scripts/icon-assets.py verify`, and commit the source and compiled assets together. The workflow does not commit artifacts automatically.

The initial catalog was compiled with Xcode 26.3 (17C529). Its compiler-generated `Recall.icns` is retained with the compiler output; the application continues to bundle the original supplied `Assets/Recall.icns` as its legacy fallback.

## Regenerate legacy raster exports

The supplied package already contains production exports. If needed, the following resamples the original artwork and may not reproduce the package's exact export bytes. It does not update the modern Icon Composer source or catalog:

```sh
swift Scripts/generate-icon.swift Assets
iconutil -c icns Assets/Recall.iconset -o Assets/Recall.icns
./Scripts/build-app.sh
```

Quit Recall before replacing the app, then reopen the replacement to refresh its running Dock icon.
