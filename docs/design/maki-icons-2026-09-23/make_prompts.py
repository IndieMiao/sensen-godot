"""Two icon prompts per high-frequency maki: one simple meaningful 3D object each."""
from pathlib import Path
TEMPLATE = """Use case: production map POI icon for a cozy mobile life-sim game.
Input image: a reference map screenshot showing the target icon style ONLY - glossy, chunky, softly rounded 3D objects (a burger, a gingerbread cookie, a movie clapperboard, a basketball, a fork and spoon) floating as map markers. Match that exact rendering style: soft studio lighting from upper left, subtle specular highlights, gentle ambient occlusion, saturated but friendly colors, clean simple shapes, no outlines. Do not reproduce the map, text, logo, or any object from the reference.
Primary request: ONE single isolated icon object: {obj}. It must instantly read as "{meaning}" at 40 pixels on a phone map. Simple silhouette, at most two or three parts, no tiny details, no base, no ground, no platform, no building unless stated.
Composition: centered, three-quarter front view slightly from above, the whole object fully visible with generous padding, square image.
Backdrop: absolutely flat uniform vivid magenta #FF00FF everywhere outside the object for chroma-key extraction. No gradient, no floor, no cast shadow on the backdrop.
Constraints: no text, no letters, no numbers, no logos, no people, no faces unless stated, no pin or badge shape behind the object, no watermark, no magenta in the object.
"""
ICONS = {
 "park": ("park / green space", ["a cute round leafy green tree with a short brown trunk", "a small wooden park bench beside a little round green bush"]),
 "restaurant": ("restaurant", ["a silver fork and spoon crossed at an angle, pastel blue handles", "a white dinner plate with a domed silver cloche lid slightly lifted"]),
 "school": ("school", ["a small stack of three colorful books with a shiny red apple on top", "a chunky yellow school backpack with two straps"]),
 "religious-christian": ("church / place of worship", ["a golden church bell with a small cream bow on top", "a simple rounded cream cross standing on a small soft pedestal"]),
 "fast-food": ("fast food", ["a juicy cheeseburger with lettuce, tomato and a sesame bun", "a red carton of golden french fries next to a soda cup with a straw"]),
 "shop": ("shop / store", ["a pastel yellow shopping bag with rope handles", "a mint green price tag with a round hole and a small string"]),
 "grocery": ("grocery / supermarket", ["a small wicker basket filled with an orange, a baguette and green leaves", "a small red shopping cart with rounded wheels"]),
 "fuel": ("gas station", ["a chunky red retro gas pump with a curled black hose and nozzle", "a red fuel jerry can with a black cap"]),
 "lodging": ("hotel / lodging", ["a cozy small bed with a fluffy white pillow and a blue blanket", "a shiny gold hotel service bell on a small round base"]),
 "cafe": ("cafe / coffee", ["a white ceramic coffee cup on a saucer with a latte-art heart and soft steam", "a takeaway coffee cup with a brown sleeve and a white lid"]),
}
for key, (meaning, objs) in ICONS.items():
    for i, obj in enumerate(objs):
        Path(f"prompt-{key}_{i + 1}.txt").write_text(TEMPLATE.format(obj=obj, meaning=meaning))
print(len(list(Path(".").glob("prompt-*.txt"))))
