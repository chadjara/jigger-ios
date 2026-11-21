#!/usr/bin/env bash
# Writes passed/failed/skipped counts from an .xcresult bundle to the job summary, because
# `xcodebuild -quiet` keeps per-test results out of the log. For each failed test it also lists the
# last steps it took (from the test's activity log), so a UI failure shows which step broke.
set -uo pipefail
label="$1"; bundle="$2"
if [ ! -d "$bundle" ]; then
  echo "### $label: no test results (the step did not run or did not get far enough to run tests)" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
xcrun xcresulttool get test-results summary --path "$bundle" --compact | python3 -c '
import json, subprocess, sys
label, bundle = sys.argv[1], sys.argv[2]
s = json.load(sys.stdin)
print("### %s: %s (%s tests: %s passed, %s failed, %s skipped)" % (
    label, s.get("result", "?"), s.get("totalTestCount", "?"), s.get("passedTests", "?"),
    s.get("failedTests", "?"), s.get("skippedTests", "?")))

def flatten(acts, depth=0):
    for a in acts or []:
        yield "  " * depth + a.get("title", "").strip()
        yield from flatten(a.get("childActivities"), depth + 1)

for f in s.get("testFailures", []) or []:
    print("- %s: %s" % (f.get("testName", "?"), f.get("failureText", "").strip()))
    test_id = f.get("testIdentifierString")
    if not test_id:
        continue
    try:
        out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "activities",
                              "--test-id", test_id, "--path", bundle, "--compact"],
                             capture_output=True, text=True, timeout=120).stdout
        runs = json.loads(out).get("testRuns", [])
        steps = [t for r in runs for t in flatten(r.get("activities")) if t]
        for t in steps[-14:]:
            print("    " + t[:200])
    except Exception as e:
        print("    (no activity log: %s)" % e)
' "$label" "$bundle" | tee -a "$GITHUB_STEP_SUMMARY"
