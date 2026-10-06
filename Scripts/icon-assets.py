#!/usr/bin/env python3
"""Record/verify the compiled icon so CLT-only builds never ship stale artwork."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
mode = sys.argv[1]
compiled = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "Assets/CompiledIcon"
source = root / "Assets/Recall.icon"
paths = sorted(path for path in source.rglob("*") if path.is_file() and path.name != ".DS_Store")
hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
catalog = compiled / "Assets.car"
manifest = compiled / "manifest.json"
if not catalog.is_file():
    sys.exit("Missing compiled icon. Run Scripts/compile-icon.sh with Xcode 26+ or download the compile-icon workflow artifact.")
data = {"sources": hashes, "catalog_sha256": hashlib.sha256(catalog.read_bytes()).hexdigest()}
if mode == "record":
    manifest.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
elif mode == "verify":
    if not manifest.is_file() or json.loads(manifest.read_text()) != data:
        sys.exit("Compiled icon is stale or modified. Regenerate it with Scripts/compile-icon.sh (Xcode 26+).")
else:
    sys.exit("Usage: icon-assets.py record|verify [compiled-directory]")
