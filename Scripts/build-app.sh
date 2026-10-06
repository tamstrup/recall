#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
Scripts/swift.sh build -c "$configuration" --product Recall
binary_dir="$(Scripts/swift.sh build -c "$configuration" --show-bin-path)"
app_dir="$PWD/build/Recall.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Recall" "$app_dir/Contents/MacOS/Recall"
cp Assets/Info.plist "$app_dir/Contents/Info.plist"
cp Assets/Recall.icns "$app_dir/Contents/Resources/Recall.icns"
cp -Rf Assets/Licenses "$app_dir/Contents/Resources/"
# Carry SwiftPM resources if a dependency adds a resource bundle.
for resource in "$binary_dir"/*.bundle(N); do
    cp -R "$resource" "$app_dir/Contents/Resources/"
done
codesign --force --deep --sign - "$app_dir"
echo "Built $app_dir"
