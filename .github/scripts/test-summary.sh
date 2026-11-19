#!/usr/bin/env bash
# Writes passed/failed/skipped counts from an .xcresult bundle to the job summary,
# because `xcodebuild -quiet` keeps per-test results out of the log.
set -uo pipefail
label="$1"; bundle="$2"
if [ ! -d "$bundle" ]; then
  echo "### $label: no test results (the step did not get far enough to run tests)" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
xcrun xcresulttool get test-results summary --path "$bundle" --compact | python3 -c '
import json, sys
label = sys.argv[1]
s = json.load(sys.stdin)
line = "### %s: %s (%s tests: %s passed, %s failed, %s skipped)" % (
    label, s.get("result", "?"), s.get("totalTestCount", "?"), s.get("passedTests", "?"),
    s.get("failedTests", "?"), s.get("skippedTests", "?"))
print(line)
for f in s.get("testFailures", []) or []:
    print("- %s: %s" % (f.get("testName", "?"), f.get("failureText", "").strip()))
' "$label" | tee -a "$GITHUB_STEP_SUMMARY"
