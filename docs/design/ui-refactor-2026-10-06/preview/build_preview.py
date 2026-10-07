#!/usr/bin/env python3
"""Inline the review data and UI so file:// can open the local catalogue.

Scene assets remain relative references into the design repository. This is
an offline repository viewer, not a standalone transferable HTML archive.
"""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
source_paths = [
    ROOT / "data/legacy-screens.json",
    ROOT / "data/current-all.json",
    ROOT.parent / "p0-flow-2026-10-05/figma/icons.json",
    ROOT / "avatar-assets/manifest.json",
    ROOT / "data/flow-repair-states.json",
    ROOT / "data/avatar-control-icons.json",
]
data = [json.loads(path.read_text()) for path in source_paths]
script = (HERE / "review.js").read_text()
lines = script.splitlines()
expected = "const [legacy,current,icons,avatarAssets,flowRepairStates,avatarControlIcons]=await Promise.all("
matches = [i for i, line in enumerate(lines) if line.startswith(expected)]
if len(matches) != 1:
    raise RuntimeError("Expected one review-data initialization to inline")
lines[matches[0]] = "const [legacy,current,icons,avatarAssets,flowRepairStates,avatarControlIcons]=" + json.dumps(data, ensure_ascii=False) + ";"
script = "\n".join(lines).replace("</script", "<\\/script")
html = (HERE / "index.html").read_text()
html = html.replace('<link rel="stylesheet" href="review.css">',
                    "<style>" + (HERE / "review.css").read_text() + "</style>")
html = html.replace('<script type="module" src="review.js"></script>',
                    '<script type="module">' + script + '</script>')
output = HERE / "review-offline.html"
output.write_text(html)
manifest = {
    "screenCount": len(data[0]) + len(data[1]),
    "legacy": len(data[0]), "current": len(data[1]),
    "supplementaryStates": len(data[4]), "avatarTrueParts": len(data[3]["parts"]),
    "dataAndCodeInlined": True, "sceneImagesRepositoryRelative": True,
    "browserVisualQa": False, "figmaRendered": False,
    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    "sources": {str(p.relative_to(ROOT.parent)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in source_paths + [HERE / "review.js", HERE / "review.css"]},
}
(HERE / "build-report.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({k: v for k, v in manifest.items() if k != "sources"}, ensure_ascii=False))
