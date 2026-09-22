"""Write one prompt per dining POI variant, sharing the approved style skeleton."""
from pathlib import Path

TEMPLATE = """Use case: stylized-concept
Asset type: production generic {label} POI sprite variant for the approved Los Angeles mobile map.
Input image 1: a cafe-area crop of the user-approved map; use its cream architecture, small collectible scale, sunny pastel palette, softly rounded dimensional materials, and three-quarter view as style guidance only. Do not reproduce the cafe, coffee cup, coast, map, or lettering.
Input image 2: the finished production {label} asset already shipped on the same map; match its material finish, soft upper-left daylight, palette family, sculpted miniature base and camera angle EXACTLY, but design a clearly DIFFERENT building — different silhouette, roof shape and layout, so the two are never mistaken for each other on the map.
Primary request: create ONE isolated {label} miniature: {building}. The building must be culturally appropriate for its category but contain no readable words. The entire compact building sits on one shallow organic pale stone and sage base. Refined matte toy/clay architectural miniature with gently rounded edges and subtle dimensional detail. Readable at around 70 pixels on a game map.
Composition: one centered complete object, square image, three-quarter isometric view from above, all roof edges, furniture and base fully visible, ample clean padding on every side. No detached pieces. The lowest edge of the base will be used as a bottom-center map anchor.
Lighting and palette: gentle diffuse daylight from upper left, warm ivory plaster base tones with the accent colors described above, pale wood details, muted teal window glass, sage plants. No magenta on the asset. No harsh shadows.
Backdrop: absolutely flat uniform vivid magenta #FF00FF outside the object for clean chroma-key extraction. No gradient, horizon, mist, backdrop texture, vignette, or shadow cast onto the backdrop.
Constraints: no readable text or lettering anywhere. No people, no characters, no UI, no pins, no surrounding city, no map roads, no coastline, no giant food objects, no watermark. One building only.
"""

VARIANTS = {
    "restaurant": ("generic restaurant", [
        "a small corner diner with a rounded cream facade, one wide muted-teal awning over a curved glass front, a tiny pergola side terrace with one round table, two sage planters, and a round plate-and-fork pictogram sign",
        "a narrow two-story bistro, ivory plaster with warm apricot shutters, a small iron balcony with flower boxes on the upper floor, a glass door below, one hanging round sign with a fork pictogram",
        "a cozy single-story eatery with a broad shallow sage-green roof, a wraparound low wooden deck with two stools at a counter window, string of tiny unlit bulbs along the eave, and a small chef-hat pictogram sign"]),
    "chinese_restaurant": ("Chinese restaurant", [
        "a small teahouse-style building with gently upturned dark jade tile eaves, cream walls, one round moon window, two tiny red lanterns flanking the wooden door, and a small steaming-bowl pictogram sign",
        "a compact two-story Chinese eatery with stacked terracotta-red tiled roofs, slim wooden lattice windows, a small entry porch with one lantern, and a folding screen door, muted gold trim accents",
        "a modest dim-sum house with a flat parapet roof and a small arched entry, pale celadon walls, a bamboo-steamer-stack pictogram sign above the door, one small red lantern and a potted kumquat tree"]),
    "cafe": ("cafe", [
        "a tiny kiosk-style espresso stand with a peaked cream canopy striped in soft butter yellow, a serving counter with two stools, a small standing menu board shape with NO text, and a coffee-cup pictogram sign",
        "a two-story corner cafe with a rooftop terrace holding one cream parasol and two chairs, warm honey wood window frames, and a round coffee-cup pictogram sign on the corner",
        "a snug cafe with a rounded barrel-vault sage roof, big arched front window, window bench with two cushions, a bicycle-free tiny porch with one potted plant, and a hanging cup pictogram sign"]),
    "bakery": ("bakery", [
        "a small mill-inspired bakery with a round tower and tiny decorative wooden windmill blades, cream walls with wheat-sheaf relief motif, a warm butter-yellow door, and a bread-loaf pictogram sign",
        "a corner patisserie with a blush-pink and cream striped awning, a big curved glass display window showing tiny pastel cake shapes, and a round croissant pictogram sign",
        "a rustic bread house with a domed stone oven attached at the side, a short brick chimney with a faint wisp of steam, warm terracotta door, flour-sack props by the entry, and a pretzel pictogram sign"]),
}

for key, (label, buildings) in VARIANTS.items():
    for i, building in enumerate(buildings):
        Path(f"prompt-{key}_{i + 2}.txt").write_text(
            TEMPLATE.format(label=label, building=building))
print("prompts written:", len(list(Path(".").glob("prompt-*.txt"))))
