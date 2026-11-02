# SGODOT-357 content 3 · Lou hand-painted keeper card (2026-10-30)

Lou, the Barbary Card Room's dealer, was the only San Francisco keeper whose greeting card was
rendered at runtime (`npc:lou`). This adds a painted card in the style of the four SGODOT-219
keeper cards (Ama, Finn, Mei, Sigrid), as 不知火舞 suggested on 351 (027fb4a1).

- Look follows Lou's accepted dealer outfit (SGODOT-357 content 1, 赵云, accepted 7714c0c7):
  black bob with the curled strand and pink tie, burgundy waistcoat, white shirt, black bow tie
  (`ref-lou-3d.png`). Scene: the green-felt card table, dealing, warm saloon interior.
- Generated through Sensenjoy `/v1/responses` (gpt-6-sol + image_generation gpt-image-2) with the
  Ama / Sigrid cards, the 3D render and the room capture as references (`prompt.txt`,
  `lou-source-1536x1024.png`, face lifted slightly as 不知火舞 suggested).
- Runtime files, matching the existing keeper files: `assets/p0/art/keepers/lou_card.jpg`
  300×660 with the 28 px rounded corners and `lou_head.jpg` 132×132 circle, both on
  (251, 248, 241). `lou-vs-keepers.png`: the five cards and heads side by side.
- Accepted by 不知火舞 (Plane 357, latest comments). The `.import` files are generated in the
  farm-dev integration (their uid depends on the path). Reading the card instead of the runtime
  render is an engineering change, assigned separately.
