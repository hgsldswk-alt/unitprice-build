"""xcresult attachments are authoritative; simulator test runner cannot always write host SHOTS_DIR."""
import json
import pathlib
import re
import shutil
import subprocess
import sys

result, output = sys.argv[1:3]
folder = pathlib.Path(output)
folder.mkdir(parents=True, exist_ok=True)
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result,
                "--output-path", str(folder)], check=True)

manifest_path = folder / "manifest.json"
if manifest_path.is_file():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    shot_name = re.compile(r"^(store-(?:zh-Hans|zh-Hant|en)-\d{2}-[a-z-]+|paid-01-paywall)(?=[_.]|$)")
    for test in manifest:
        for attachment in test["attachments"]:
            match = shot_name.match(attachment.get("suggestedHumanReadableName", ""))
            source = folder / attachment["exportedFileName"]
            if match and source.suffix.lower() == ".png":
                target = folder / (match[1] + ".png")
                if source.resolve() != target.resolve():
                    shutil.copy2(source, target)

pngs = list(folder.glob("**/*.png"))
if not pngs:
    sys.exit("界面测试没有导出 PNG 截图")
for index, path in enumerate(sorted(pngs), 1):
    if path.parent != folder:
        shutil.copy2(path, folder / f"{index:03d}-{path.name}")
print(f"已导出 {len(pngs)} 张界面测试截图到 {folder}")
