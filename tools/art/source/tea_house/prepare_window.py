"""Preserve a source-identifiable window scenery crop from the approved concept."""
from pathlib import Path
import json
from PIL import Image

SRC=Path(__file__).resolve().parent
image=Image.open(SRC/'reference/216-tea.png').convert('RGB')
crop=(245,370,310,460)
image.crop(crop).resize((512,512),Image.Resampling.LANCZOS).save(SRC/'reference/window-view.png')
(SRC/'reference/window-view.json').write_text(json.dumps({'source':'216-tea.png','crop_xyxy':crop,
    'purpose':'Separate replaceable window-only scenery; crop is illustrative, not a dimension reference'},indent=2)+'\n')
