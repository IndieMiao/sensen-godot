"""Compose native Godot screenshots; run with `uv run --with Pillow python ...`."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
output = ROOT / "output/mine-art-2026-09-24"
font_path = str(ROOT / "assets/ui/fonts/NotoSansSC-Regular.otf")
font = ImageFont.truetype(font_path, 30)
small = ImageFont.truetype(font_path, 22)
sheet = Image.new("RGB", (1800, 1090), "#242125")
draw = ImageDraw.Draw(sheet)
draw.text((42, 22), "矿坑美术调整 · Godot 实时渲染", font=font, fill="#f2e8da")
labels = ["B1 赤陶矿室", "B2 苔石矿室", "B3 蘑菇矿室", "B4 蓝晶矿室", "B5 紫晶精英矿室"]
for index, label in enumerate(labels):
    image = Image.open(output / "after" / f"chamber-{index+1}.png").convert("RGB")
    image = image.resize((600, 450), Image.Resampling.LANCZOS)
    x = index * 600 if index < 3 else 300 + (index - 3) * 600
    y = 76 if index < 3 else 585
    sheet.paste(image, (x, y))
    draw.text((x + 28, y + 448), label, font=small, fill="#d6c8bf")
sheet.save(output / "five-floors.png")
comparison = Image.new("RGB", (1920, 792), "#242125")
draw = ImageDraw.Draw(comparison)
for index, (phase, label) in enumerate([("before", "调整前"), ("after", "调整后")]):
    draw.text((index * 960 + 32, 16), label, font=font, fill="#f2e8da")
    comparison.paste(Image.open(output / phase / "chamber-1.png").convert("RGB"), (index * 960, 72))
comparison.save(output / "before-after.png")
