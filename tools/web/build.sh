#!/usr/bin/env bash
# Export the web build and lay it out for the Artifact page: wasm and pck split into
# <=12.5 MB parts (the per-file publish limit), page shell filled in.
# Usage: GODOT=/path/to/godot4.3 tools/web/build.sh BUILD_NUMBER
set -euo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build number}
G=${GODOT:-godot}
rm -rf build/web build/page && mkdir -p build/web build/page/wasm build/page/pck
"$G" --headless --export-release Web build/web/index.html
split -b 13000000 -d -a 1 build/web/index.wasm build/page/wasm/part && for f in build/page/wasm/part?; do mv "$f" "$f.wasm"; done
split -b 12500000 -d -a 1 build/web/index.pck build/page/pck/b$B- && for f in build/page/pck/b$B-?; do mv "$f" "$f.wasm"; done
cp build/web/index.js build/web/index.audio.worklet.js build/page/
PARTS=$(cd build/page && ls pck/*.wasm | sort -V | sed 's/.*/"&"/' | paste -sd, -)
SIZE=$(stat -c %s build/web/index.pck)
sed -e "s|__PCK_PARTS__|[$PARTS]|" -e "s|__PCK_SIZE__|$SIZE|" -e "s|__BUILD__|$B|" tools/web/index.html > build/page/index.html
ls -la build/page build/page/wasm build/page/pck
