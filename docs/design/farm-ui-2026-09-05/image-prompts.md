# Image Generation Record

2026-09-05. The user authorized generation using the existing `sensenjoy` configuration. This replaces the earlier unexecuted briefs.

## Execution

- Mode: authorized CLI/API fallback; screenshot-based edits through the bundled `imagegen/scripts/image_gen.py`.
- Provider: `sensenjoy`, base URL `https://sub.sensenjoy.cn/v1`.
- Endpoint: `POST /images/edits` relative to that base URL.
- Requested model: `gpt-image-2` (listed by the provider's models endpoint).
- Requested settings: `quality=high`, `size=2048x1536`, `output_format=png`, one result per call, `--no-augment`.
- Credentials: existing `SENSENJOY_API_KEY` exposed to the CLI as `OPENAI_API_KEY` for each process. No credentials are stored in these files.
- Canonical review copies: [generated/](generated/). Working outputs and initial versions: ignored `output/imagegen/farm-ui/`.
- Images are AI design concepts derived from game screenshots. They are not screenshots of implemented UI.

The provider returned dimensions different from the requested size. The delivered PNGs retain their actual native dimensions; they have not been upscaled to imply additional detail.

## Prompts and References

| Board | Original Prompt | Screenshot References | Targeted Refinement |
| --- | --- | --- | --- |
| [Map](generated/map-design.png) | [01-map.txt](prompts/01-map.txt) | [map-online.png](map-online.png) | None |
| [Farm](generated/farm-design.png) | [02-farm.txt](prompts/02-farm.txt) | [farm.png](farm.png), [movement.png](movement.png) | [02-farm-refinement.txt](prompts/02-farm-refinement.txt): preserve nine plots, correct sow-ready soil and action glyphs |
| [Panels and Visitor](generated/panels-design.png) | [03-panels.txt](prompts/03-panels.txt) | [stall.png](stall.png), [goals.png](goals.png), [visitor.png](visitor.png) | [03-panels-refinement.txt](prompts/03-panels-refinement.txt): correct lettuce sale and seed prices |
| [Secondary Flows](generated/secondary-design.png) | [04-secondary.txt](prompts/04-secondary.txt) | [city-reference.png](city-reference.png), [dressing-reference.png](dressing-reference.png), [farm.png](farm.png) | [04-secondary-refinement.txt](prompts/04-secondary-refinement.txt): remove decorative containers inside the director modal |

Each initial refinement uses the corresponding first generated board as its sole edit target. The farm board also received a [final localized edit](prompts/02-farm-final.txt), using its second version as input, to restore the ninth plot and move the avatar into the margin. Original prompt text is preserved verbatim in the linked files. The city and dressing references were captured on the Android emulator; the farm reference was captured on the vivo device.

The farm's seven-glyph legend was then normalized locally using the existing Lucide SVG files (`scissors`, `shovel`, `sprout`, `droplet`, `cloud-rain`, `wind`, `wheat`). Playwright rasterized those exact glyphs; Pillow composited only the rectangle `(1080, 724)-(1424, 776)` onto the 1448 x 1086 AI board. No other pixels were changed during this step. This small postprocessing step avoids treating inaccurate generated symbols as icon source assets.

## Delivered Images

| File | Native Size | Selected Version |
| --- | --- | --- |
| `generated/map-design.png` | 1536 x 1024 | First generation |
| `generated/farm-design.png` | 1448 x 1086 | Third generation plus the Lucide legend normalization |
| `generated/panels-design.png` | 1448 x 1086 | Second generation, prices corrected |
| `generated/secondary-design.png` | 1448 x 1086 | Second generation, director rows simplified |

All four boards were inspected visually. The farm board shows nine plots in each viewport; stall prices use radish 8/4 and lettuce 12/6 for sale/seed costs. The gallery is checked separately at desktop and mobile sizes.

## Reproduction

Run from the repository root with the existing provider credential available in the environment. This example generates a new map output without overwriting the reviewed image:

```sh
OPENAI_API_KEY="$SENSENJOY_API_KEY" \
OPENAI_BASE_URL="https://sub.sensenjoy.cn/v1" \
uv run --with openai --with pillow python \
  /Users/zhangshaojie/.codex/skills/.system/imagegen/scripts/image_gen.py edit \
  --model gpt-image-2 \
  --image docs/design/farm-ui-2026-09-05/map-online.png \
  --prompt-file docs/design/farm-ui-2026-09-05/prompts/01-map.txt \
  --no-augment --size 2048x1536 --quality high \
  --out output/imagegen/farm-ui/map-design-new.png
```

For another board, use the corresponding prompt and repeat `--image` in the reference order in the table. For a refinement, supply the initial generated board and its refinement prompt. Image generation is nondeterministic, so rerunning the command will not reproduce identical pixels.

The [gallery](index.html) provides the final review images. Runtime behavior and physical-device verification remain documented separately in [README.md](README.md).
