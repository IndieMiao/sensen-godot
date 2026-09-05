# Secondary Screens: Design QA Draft

This section is a draft for the final design QA report; it does not replace the root report.

Comparison artifact: [secondary-comparison.png](secondary-comparison.png). Approved city and dressing screens are cropped from `generated/secondary-design.png`. Runtime images are actual Godot captures at 360x800 with simulated notch safe areas. Every image is scaled proportionally to the same 800px height; no image is stretched.

## Matched

- City selection uses a full-screen garden street and three clearly separated choices, with no enclosing marketing panel.
- Dressing keeps a real 3D avatar in the central room, a clear title and Done action, five evenly distributed icon tabs, and a complete three-column/two-row thumbnail grid.
- At both 360x640 and 360x800, controls stay within the safe area, both thumbnail rows remain visible, and selected item labels fit their actual StyleBox content bounds. The shorter viewport uses a smaller fixed thumbnail size, not a reduced font size.
- Room scenery is independent of the avatar camera. A 24,220-pixel background edge region is identical between the final full-body and head-focus captures. The highest hat remains visible during head focus.

## Remaining Visual Differences

- The generated city and room backgrounds are more realistic and have finer surface detail than the softly illustrated approved board. Their subjects, light direction, side framing and central open areas follow the board.
- The implementation uses a darker forest-green primary action; the board uses a lighter mint/teal fill. The native font is Nunito at weight 650; action icons come from the existing Lucide family. Hair and shoes use scissors/footprints symbols instead of the board's custom hair/shoe glyphs.
- The city choice group sits lower, leaving more clear sky above it. The dressing thumbnail grid is denser and its thumbnails are smaller than the design board, allowing all six choices to remain visible on the 640px-tall phone layout.
- The approved city screen shows a gold outline and a right-side check on Shanghai. The current flow immediately opens the map on a city tap, so there is no persistent selected-city state on this screen.
- The approved dressing thumbnail has a small corner check. The implementation communicates selection with a green outline, green label and the live avatar; it does not add the corner check.
- Reset is an additional 48px icon action in the runtime header, between the title and Done. It retains the existing outfit reset function and has a tooltip.

## Interaction Evidence

The directed city, dressing layout, camera and dressing-flow run passed 44 cases in `reports/report_733/results.xml`. It covers control hit testing, selection, stable equipment framing, draft cancellation, waiting for assembly before saving, and save failure handling. This comparison work did not launch Godot or change application code; final physical-device installation and validation are performed by the root task.
