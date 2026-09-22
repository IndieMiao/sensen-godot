from pathlib import Path
T = """Use case: stylized-concept
Asset type: one production landmark sprite for a mobile Shanghai map, part of a set whose Los Angeles landmarks are already shipped.
Input images: Image 1 and Image 2 are finished landmark sprites from the same game (Griffith Observatory, Santa Monica Pier). Match their exact visual language: premium soft matte pastel clay-toy miniature, gently rounded edges, clean readable massing, delicate detail, a very low compact pale mint landscaped base, three-quarter elevated isometric camera, soft daylight from upper left. Do not reproduce their subjects.
Subject: {subject}
Composition: one isolated landmark, entire object and base fully visible, centered, at least 12 percent empty margin, readable silhouette at small map icon size.
Backdrop: absolutely flat uniform vivid magenta #FF00FF outside the object for chroma-key extraction; no gradient, no floor, no shadow on the backdrop, no magenta in the object.
Constraints: no text, no letters, no signage lettering, no people, no vehicles, no watermark, no surrounding city.
"""
S = {
 "oriental_pearl_tower": "a recognizable Oriental Pearl TV Tower of Shanghai: tall slender pink-and-silver tower with its distinctive stacked pink spheres (a large lower sphere, a large upper sphere and a small top sphere) on three angled support columns, topped by a thin antenna spire, on a small round landscaped base.",
 "the_bund": "a recognizable short row of three historic neoclassical Bund waterfront buildings of Shanghai in warm cream stone, including the domed customs-house style clock tower building, arched windows, a strip of riverside promenade with a low balustrade in front, all on one low base.",
 "yu_garden": "a recognizable Yu Garden pavilion of Shanghai: a classical Chinese two-tier pavilion with sweeping upturned dark grey tile eaves and red wooden columns, a zigzag stone bridge over a tiny pond, a scholar's rock and a small willow, on one low base.",
 "shanghai_tower": "a recognizable Shanghai Tower: a tall twisting spiral glass skyscraper in pale blue-silver glass with a gentle curved notch spiralling to the top, softly stylized, on a small landscaped base.",
 "jingan_temple": "a recognizable Jing'an Temple of Shanghai: a golden-roofed Buddhist temple hall with bright gold curved roofs, cream walls and a small golden pagoda-like spire behind, on one low base.",
}
for k, v in S.items(): Path(f"prompt-{k}.txt").write_text(T.format(subject=v))
