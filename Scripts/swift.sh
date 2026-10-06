#!/bin/zsh
set -euo pipefail
# The macOS 27 Command Line Tools omit SwiftUIMacros. The bundled 26.5 SDK
# uses the compatible State property wrapper and supports Foundation Models.
args=()
if [[ "$(xcode-select -p)" == */CommandLineTools && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    args+=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
    args+=(-Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing")
fi
command="$1"
shift
exec swift "$command" "${args[@]}" "$@"
