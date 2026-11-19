#!/usr/bin/env bash
# Installs the pinned XcodeGen release into ~/.xcodegen (cached between runs) and adds it to PATH.
set -euo pipefail
dest="$HOME/.xcodegen"
if [ ! -x "$dest/bin/xcodegen" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 -o "$tmp/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
  unzip -q "$tmp/xcodegen.zip" -d "$tmp"
  rm -rf "$dest" && mkdir -p "$dest"
  cp -R "$tmp/xcodegen/." "$dest/"
fi
echo "$dest/bin" >> "$GITHUB_PATH"
"$dest/bin/xcodegen" --version
