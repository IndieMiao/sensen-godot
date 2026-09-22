"""One prompt per POI variant (#5..20 for dining, #2..20 for museum), shared style skeleton."""
from pathlib import Path

TEMPLATE = """Use case: stylized-concept
Asset type: production generic {label} POI sprite variant for the approved Los Angeles mobile map.
Input image 1: a cafe-area crop of the user-approved map; use its cream architecture, small collectible scale, sunny pastel palette, softly rounded dimensional materials, and three-quarter view as style guidance only. Do not reproduce the cafe, coffee cup, coast, map, or lettering.
Input image 2: a finished production {label} asset already shipped on the same map; match its material finish, soft upper-left daylight, palette family, sculpted miniature base and camera angle EXACTLY, but design a clearly DIFFERENT building - different silhouette, roof shape and layout - so the two are never mistaken for each other on the map.
Primary request: create ONE isolated {label} miniature: {building}. It must read clearly as a {label} at small size, with a small round {sign} pictogram sign and no readable words. The entire compact building sits on one shallow organic pale stone and sage base. Refined matte toy/clay architectural miniature with gently rounded edges and subtle dimensional detail. Readable at around 70 pixels on a game map.
Composition: one centered complete object, square image, three-quarter isometric view from above, all roof edges, furniture and base fully visible, ample clean padding on every side. No detached pieces. The lowest edge of the base will be used as a bottom-center map anchor.
Lighting and palette: gentle diffuse daylight from upper left, warm ivory plaster base tones with the accent colors described above, pale wood details, muted teal window glass, sage plants. No magenta on the asset. No harsh shadows.
Backdrop: absolutely flat uniform vivid magenta #FF00FF outside the object for clean chroma-key extraction. No gradient, horizon, mist, backdrop texture, vignette, or shadow cast onto the backdrop.
Constraints: no readable text or lettering anywhere. No people, no characters, no UI, no pins, no surrounding city, no map roads, no coastline, no giant food objects, no watermark. One building only.
"""

CATS = {
 "restaurant": ("generic restaurant", "plate-and-fork", 5, [
  "a Spanish-colonial eatery with white stucco arches, a terracotta barrel-tile roof and a shaded arcade with two tables",
  "a retro streamline diner with a rounded chrome-trimmed corner, pastel mint panels and a long band of windows",
  "a tiny A-frame roadside grill with a steep dark wood roof and a small wooden deck with a picnic table",
  "a craftsman bungalow restaurant with a low gabled roof, deep front porch, tapered columns and hanging plants",
  "a glass-walled modern bistro box with a thin flat roof, pale wood slat screen and a roof garden",
  "a brick warehouse gastropub with a sawtooth roof, big steel-framed windows and a roll-up door open to a patio",
  "a Mediterranean taverna with blue-shuttered windows, a vine-covered pergola and whitewashed stepped walls",
  "a round pavilion restaurant with a conical copper-green roof and wraparound windows",
  "a two-story Victorian-style restaurant with a turret, scalloped shingles in dusty rose and a bay window",
  "a food-truck-inspired stall: a rounded vintage van converted into a permanent kitchen with an awning and two stools",
  "a Japanese-style izakaya with a low dark tile roof, wooden lattice front, noren curtain and a single paper lantern",
  "a Mexican cantina with an adobe body, rounded parapet, bright marigold trim and a small tiled fountain",
  "a steakhouse lodge with a stone chimney, heavy timber beams and a green shingle roof",
  "a seaside-style fish shack with pale blue clapboard, a rope-trimmed porch and a lobster-trap stack",
  "a pizzeria with a domed brick pizza oven on the side, red-and-cream striped awning and a small herb garden",
  "a rooftop-terrace restaurant on a narrow three-story cream building with parasols on top",
 ]),
 "chinese_restaurant": ("Chinese restaurant", "steaming-bowl", 5, [
  "a single-story courtyard eatery with a moon gate entry, grey tile roof and a small bonsai",
  "a noodle house with a vermilion wooden facade, gold trim and stacked red lanterns under a hip roof",
  "a hot-pot restaurant with a round tower-like corner, jade green tiles and a large circular window",
  "a Cantonese tea house with a two-tier pagoda roof in dark teal and cream balustrades",
  "a dumpling kiosk with a small upturned-eave canopy, bamboo screens and bamboo steamer stacks by the door",
  "a Lingnan-style arcade shophouse with a covered walkway, carved window grilles and pastel ochre walls",
  "a garden pavilion restaurant over a tiny koi pond with a zigzag bridge to the door",
  "a Beijing hutong-style eatery with a grey brick wall, red double doors with brass knockers and a tiled gate roof",
  "a modern Chinese bistro with a flat roof, cream walls, a single jade circle window and a slim red lantern",
  "a two-story Shanghai shikumen-style building with a stone door frame, dark wood doors and a small balcony",
  "a Sichuan restaurant with chili-red lanterns strung across a timber porch and a dark tiled roof",
  "a noodle bar with a curved wooden counter window, hanging lanterns and a stack of noodle bowls on a shelf",
  "a Hakka round-house-inspired compact eatery with a circular earthen wall and tiled ring roof",
  "a bao shop with a steamer-shaped domed roof ornament, cream walls and teal trim",
  "a Chinese bakery-cafe hybrid with a small pagoda cupola on a flat roof and a red awning",
  "a riverside-style eatery on short wooden stilts with a boat-shaped roof and paper lanterns",
 ]),
 "cafe": ("cafe", "coffee-cup", 5, [
  "a Parisian corner cafe with a mansard slate roof, wrought-iron balcony and bistro chairs out front",
  "a greenhouse cafe made of arched glass panels with plants inside and a white frame",
  "a Scandinavian cabin cafe with a steep black roof, pale wood cladding and a big picture window",
  "a surf-shack coffee stand with a palm-thatch roof, turquoise counter and two surfboards leaning on it",
  "a tiny round coffee drum-kiosk with a striped conical roof like a carousel",
  "a brick-and-steel roastery cafe with a small chimney, burlap coffee sacks and a big roasting drum visible in the window",
  "a cottage cafe with a thatched roof, round door and a flower-lined path",
  "a Mid-century modern cafe with a butterfly roof, breeze-block wall and orange accent panels",
  "a book cafe with tall arched windows filled with bookshelves and a green roof",
  "a tea-and-coffee pavilion with a hexagonal roof, open sides and cushioned benches",
  "a double-decker-bus-inspired cafe: a rounded cream vehicle body turned permanent kiosk with an upstairs seat deck",
  "a Moroccan-style cafe with a horseshoe arch door, blue-and-white tiles and a small dome",
  "a hillside terrace cafe on stepped platforms with parasols and potted lemon trees",
  "a Japanese kissaten with a dark wood front, round lamp and a small Zen gravel patch",
  "a Spanish mission-style cafe with a bell-shaped gable, stucco and a courtyard fountain",
  "an ice-cream and coffee parlor with a candy-pink scalloped awning and a giant cone-shaped roof finial",
 ]),
 "bakery": ("bakery", "bread-loaf", 5, [
  "a French boulangerie with a deep blue facade, gold trim and baguette baskets by the door",
  "a gingerbread-style cottage bakery with icing-white trim and a candy-cane striped porch post",
  "a donut shop with a large ring-shaped decorative roof sign shape (no words) and pastel pink walls",
  "a Tudor half-timbered bakery with dark beams, cream plaster and a bay window of pies",
  "a cupcake boutique with a scalloped mint roof like frosting and a round display window",
  "a Danish bakery with a steep red roof, white window cross-frames and a pretzel sign",
  "a farmhouse bakery with a barn-red gable, flour sacks and a small wooden cart of loaves",
  "a Mexican panaderia with pastel-yellow adobe, arched doorway and trays of conchas in the window",
  "a Japanese bakery with a clean white box shape, pale wood awning and melon-bun display",
  "a stone-arch vaulted bakery like an old oven house with a round front arch and glowing interior",
  "a two-story corner bakery with a green copper cupola and striped awnings on both sides",
  "a waffle-and-crepe stand with a folded-paper-like roof and a small griddle counter",
  "a Middle Eastern bakery with a flat roof, arched lattice windows and flatbread baskets",
  "a rustic log-cabin bakery with a mossy roof and a wood stack beside the oven",
  "a pie shop with a lattice-crust-patterned roof and a cherry-red door",
  "a cake atelier with a tiered roofline like a wedding cake in cream and blush",
 ]),
 "museum": ("museum", "classical-column", 2, [
  "a small neoclassical museum with a white columned portico, triangular pediment and wide front steps",
  "a modern art museum made of stacked offset white boxes with one large glass wall",
  "a natural-history museum with a domed rotunda and a small dinosaur skeleton sculpture on the lawn",
  "a science museum with a planetarium dome and a small telescope on the roof",
  "a maritime museum with a ship-bow shaped wing, porthole windows and an anchor on the base",
  "an adobe mission museum with a bell tower and a cloister arcade",
  "a curved white ribbon-like contemporary gallery with a sweeping roof",
  "a red-brick industrial heritage museum with a tall chimney and arched windows",
  "a children's museum with colorful rounded blocks, a slide and playful porthole windows",
  "a glass pyramid entrance pavilion museum on a stone plaza",
  "an Art Deco museum with stepped setbacks, sunburst reliefs and teal-and-gold trim",
  "a Japanese-style museum pavilion with a long low roof over a reflecting pool",
  "a train museum: a small station house with a vintage locomotive parked beside it",
  "an automobile museum with a streamlined facade and a classic car on a display plinth",
  "a castle-like history museum with crenellated towers in pale sandstone",
  "a sculpture garden museum: a small pavilion with abstract sculptures on the lawn",
  "an aviation museum hangar with a curved roof and a small propeller plane outside",
  "a craftsman-style house museum with a wide porch and period lanterns",
  "a hilltop observatory-like museum with a copper dome and a columned drum",
 ]),
}

for key, (label, sign, start, buildings) in CATS.items():
    for i, building in enumerate(buildings):
        Path(f"prompt-{key}_{start + i}.txt").write_text(TEMPLATE.format(label=label, sign=sign, building=building))
print(len(list(Path(".").glob("prompt-*.txt"))))
