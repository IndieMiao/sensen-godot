#!/usr/bin/env python3
"""Write docs/design/tokens/tokens-v2.json from the object returned by tools/ui/export_tokens_figma.js
(SGODOT-211). Reads {"fnv1a", "bytes", "compact"} JSON on stdin, pretty-prints `compact` exactly like
JSON.stringify(tokens, null, 2) + "\\n", and refuses to write unless the FNV-1a hash and length match the
export, so a copied result can never drift from what Figma returned."""
import json, sys, pathlib

def fnv1a(text: str) -> str:
    h = 0x811c9dc5
    for ch in text:
        h ^= ord(ch)
        h = (h * 0x01000193) & 0xffffffff
    return format(h, 'x')

result = json.load(sys.stdin)
pretty = json.dumps(json.loads(result['compact']), indent=2, ensure_ascii=False) + '\n'
if fnv1a(pretty) != result['fnv1a'] or len(pretty) != int(result['bytes']):
    sys.exit(f"checksum mismatch: {fnv1a(pretty)} / {len(pretty)} vs {result['fnv1a']} / {result['bytes']}")
# An optional path writes elsewhere (a re-export to compare before it replaces the tokens: 不知火舞 340 021fbb31).
out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2] / 'docs/design/tokens/tokens-v2.json'
out.write_text(pretty)
print(f"wrote {out} ({len(pretty)} bytes, fnv1a {result['fnv1a']})")
