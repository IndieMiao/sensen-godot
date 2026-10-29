# SGODOT-324 Hall Kit v1

Provisional reusable props by Huang Zhong. Eight families, ten variants; no room shell.

Use `hall_opaque.tres` for Body / Artwork and `hall_glass.tres` for Glass. Disable Glass shadow casting. All materials reference one 2048-square Basic Room palette. Final hall atlas and colours are pending SGODOT-319; no room-contact AO is included yet.

Floor assets use Y=0 at the lowest vertex. Wall assets use Z=0 at the back mounting plane and Y=0 at the mounting centre. Y is up, +Z faces forward; metres, scale 1.

`asset_stats.json` records decoded bounds, triangles, anchors and per-part palette assignments. Each asset has its own `provenance/<asset>/reuse_provenance.json`. Frame Artwork nodes are independently replaceable. Glass nodes include closed ends and backs; the cabinet top closes the bottom.

Full measurements, source, validation, images and reproduction: [SGODOT-324 review](../../../../docs/design/poi-hallkit-324-2026-10-29/README.md).
