#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
output="${1:-$PWD/Assets/CompiledIcon}"
if ! xcrun --find actool >/dev/null 2>&1; then
    echo "Regenerating the modern icon requires Xcode 26+. Ordinary builds use Assets/CompiledIcon."
    exit 1
fi
mkdir -p "$output"
xcrun actool Assets/Recall.icon --compile "$output" --app-icon Recall \
    --minimum-deployment-target 14.0 --platform macosx --target-device mac \
    --output-partial-info-plist "$output/compiler-info.plist" \
    --output-format human-readable-text --errors --warnings --notices
python3 Scripts/icon-assets.py record "$output"
python3 Scripts/icon-assets.py verify "$output"
xcodebuild -version > "$output/compiler-version.txt"
