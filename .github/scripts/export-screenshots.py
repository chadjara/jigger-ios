"""Copies screenshots attached by ScreenshotTests out of an exported .xcresult attachment folder,
naming them by their attachment name (e.g. iPhone-01-calculator.png), and prints their pixel sizes."""
import json
import pathlib
import shutil
import struct
import sys

src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
count = 0
for test in json.loads((src / "manifest.json").read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        if not name.startswith(("iPhone-", "iPad-", "Duo-")):
            continue
        out = dest / (name.split("_")[0] + ".png")
        shutil.copyfile(src / a["exportedFileName"], out)
        with open(out, "rb") as f:
            header = f.read(24)
        width, height = struct.unpack(">II", header[16:24])
        print(f"{out.name}: {width} x {height}")
        count += 1
if count == 0:
    sys.exit("No screenshots were found in the test results.")
