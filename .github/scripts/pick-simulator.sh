#!/usr/bin/env bash
# Prints the UDID of an available simulator whose name starts with $1 ("iPhone" or "iPad"),
# on the newest installed iOS runtime, so device-name changes on the runner never break CI.
set -euo pipefail
kind="$1"
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
kind = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d["name"].startswith(kind) and d.get("isAvailable", True):
            # newest runtime first, then the plainest model name (e.g. "iPhone 17", "iPad (A16)")
            key = (version, -len(d["name"]))
            if best is None or key > best[0]:
                best = (key, d["udid"], d["name"])
if best is None:
    sys.exit("No " + kind + " simulator is available")
print(best[1])
print("Using %s on iOS %d.%d" % (best[2], best[0][0][0], best[0][0][1]), file=sys.stderr)
' "$kind"
