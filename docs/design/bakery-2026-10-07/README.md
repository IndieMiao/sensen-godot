# SGODOT-175 · Bakery R2.1 finishing review

> 当前炉火已切换为共享粒子特效；本页保留此前美术/挂点/糕点评审证据。最新整景、近景录像、粒子预算与不重烘校验见[共享炉火交付](../bakery-fire-2026-10-08/README.md)。

赵云 · **R2.1 / Review**。按最新复审完成糕点分层、颜色、盆栽遮挡与面包割纹修正，已补齐实际Godot实渲、固定取色和新的走位录像。Reference: Figma `OMLTC3yw3u2WDjOZhLnhaR`, SceneDesign, node `545:2964`.

![Reference / revised Godot / direct 50% overlay](comparison.png)

[Whole room](godot.png) · [Oven and workbench](detail-oven.png) · [Stocked curved display](detail-pastries.png) · [Model orthographics](orthographic-sheet.png).

| Review requirement | Change |
|---|---|
| Structure and palette | Removed the Basic Room corner posts, post caps and beam brackets. Continuous apricot plaster walls meet at a bare plaster corner; red-brown top trim and 31 rows of narrower staggered reddish planks replace the former warm timber frame. |
| Oven | Wider cream/apricot domed masonry oven, real arched mouth and lower wood-storage cavity, brick mouth voussoirs, brick chimney with mortar, hearth ledge, visible stored logs and peel. Orange gradient flames and a short-range warm OmniLight light the baking loaves and preparation area. |
| Pastry display | Curved glass and metal outline enclose **24 pastries from 11 editable linked prototypes**. Lower layer: croissants, loaves and baguettes; middle: pink/green/yellow macarons plus strawberry/lemon tarts; upper: white-pink cake slices, cream strawberry cakes and tarts with one chocolate cake. The three sequences differ, with varied yaw, scale and offsets. Named prototypes remain in Blender's PROTOTYPE collections; display placements batch into one local-pivot runtime zone. Glass opacity is .045, retaining visibility of the food. |
| Bread rack and jars | Five metal rack levels with bread and staggered baguettes/croissants; adjacent shelf has 24 jars/bottles of varied heights and colours. Back pantry adds six jars plus baskets of upright baguettes. |
| Working props | Dough, rolling pin, utensils, mixing bowl, an actual dial scale, metric folded checked towel, FLOUR sack and wicker storage under the workbench. |
| Sign and lights | Nunito Black rounded-bold 4mm-extruded BAKERY lettering on a curved cream wall-mounted plaque with red wood border and wheat motif; two black curved wall lights, green enamel pendant on a long cord and orange oven light. Blackboard reads Good / Bread / Brighter / Days. |
| Cafe and plants | Two bentwood chairs with curved backs and green pads, round cafe table/cup/daisies and a braided round rug. Two shared olive trees by the left seating, peace lily moved to the right of the checkout counter, shared window/pantry pothos. Shared library is consumed without edits. |

R2.1 also replaces all raised white loaf/baguette slashes with actual shallow boolean grooves and warm crumb faces, one colour step lighter than crust. The source audit found 29 scored source objects (including prototypes) and zero old white-score bars. In the unchanged hero camera, the relocated plant's projected bounds start 114px beyond the display's right edge; the new actual Godot full view and detail confirm the clear display front. [Revision inventory and source audit](../bakery-review21-2026-10-08/source-audit.json).

The camera fits three declared plinth corners; the rear corner is inferred. Whole-reference containment and direct 50% overlay use no image warping. The concept's single stylized view leaves residual upper-wall and furniture-position differences for review; [camera data](../../../tools/art/source/bakery/camera-review.json) records the fit.

[Marked fixed samples](colour-samples.png) and [RGB/HSV measurements](colour-verification.json) cover left/right plaster, red-brown trim and horizontal floor. Before tuning, a misplaced reference sample on a timber pantry ledge was reclassified to the actual plaster beside the left lamp; this correction is documented in `colour-patches.json`. The resulting fixed plaster sample initially measured 10.043° after the final lighting revision, so its material was warmed toward peach at the same sample point. Final fixed samples: **7.997° / 7.813° / 4.226° / 3.731°**, all ≤10°.

**181,235 total triangles / 31,154 botanical triangles / 40 static surfaces**. [Budget/UV/normals/hash verification](verification-summary.json) enforces ≤200,000 total triangles, ≤100,000 botanical triangles and ≤60 static surfaces. Botanical budget conservatively includes the complete flower-containing cafe/wall module. Source geometry remains named/editable, with explicit local pivots and no atlas embedded in the delivered GLBs.

**A fresh R2.1 run passes 34/34 rendered character checks and the 15-second real-time route video.** The art scene owns a controlled front entrance and supporting exterior pad, remaining perimeter boundaries and furniture blockers. Actual character traversal goes from the front to pastry display/cashier, around the workbench and to the cafe. The narrowest authored workbench/display overlap has **1.08095m** clear width, above .80m. [Rendered checks](bench-result.json), [live scales](bench-scale-measurements.json), [source dimensions](source-scale.json), [cloth UV ratios](cloth-uv-verification.json), [collision view](bench-collisions.png) and [15-second real-time video frames](video-frames.png) are supplied.

Door scale is explicitly inapplicable to this open-front shop. Checkout top 1.15m, cafe seat .73m, cafe tabletop 1.0024m all remain within ±15% of the accepted Basic Room category; preparation workbench is 1.035m. Capsule .21m radius/1.25m height and 3.75m/s speed remain unchanged.

Rebuild `tools/art/build_bakery.py`, which delegates to `source/bakery/revision.py`; use Blender's `measure_room_source.py -- bakery`, then the isolated Godot review and scene_bench workflow. Final checks/package: `check_room_colour.py bakery 175` and `package_room_review.py bakery 175` (Pillow/NumPy required).

Godot 4.7.2 Mobile/Vulkan on AMD Custom GPU 0405 / RADV VANGOGH. Desktop behavior and appearance review only; no production/gameplay/save changes or physical-phone performance acceptance. Basic Room and Liu Bei assets remain read-only.
