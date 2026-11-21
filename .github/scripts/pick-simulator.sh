#!/usr/bin/env bash
# Prints the UDID of an available simulator whose name starts with $1 (e.g. "iPhone", "iPad", "iPhone Duo"),
# on the newest iOS runtime the selected Xcode's SDK can run, so device-name changes on the runner never break CI.
set -euo pipefail
kind="$1"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
kind, sdk = sys.argv[1], tuple(int(x) for x in sys.argv[2].split(".")[:2])
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)$", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    if version > sdk:
        continue  # newer than the SDK we build with
    for d in devices:
        if d["name"].startswith(kind) and d.get("isAvailable", True):
            # "iPhone" must not pick the iPhone Duo; ask for "iPhone Duo" explicitly.
            if kind == "iPhone" and d["name"].startswith("iPhone Duo"):
                continue
            # newest runtime first, then the plainest model name (e.g. "iPhone 17", "iPad (A16)")
            key = (version, -len(d["name"]))
            if best is None or key > best[0]:
                best = (key, d["udid"], d["name"])
if best is None:
    sys.exit("No " + kind + " simulator is available for iOS " + sys.argv[2])
print(best[1])
print("Using %s on iOS %d.%d" % (best[2], best[0][0][0], best[0][0][1]), file=sys.stderr)
' "$kind" "$sdk"
