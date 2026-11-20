from pathlib import Path
import json,importlib.util
from shapely.geometry import box,Polygon
from shapely.ops import unary_union
from generator import preserves_source_topology
from audit_source_geometry import verify_topology
R=Path(__file__).resolve().parents[1]
outer=Polygon(box(0,0,60,60).exterior.coords,[box(10,10,50,50).exterior.coords]);inner=Polygon(box(20,20,40,40).exterior.coords,[box(25,25,27,27).exterior.coords]);source=unary_union([outer,inner]);extra_ring=Polygon(box(11,11,49,49).exterior.coords,[box(12,12,48,48).exterior.coords]);candidate=unary_union([outer,box(20,20,40,40),extra_ring])
def cells(g):return {(x,y) for x in range(60) for y in range(60) if g.covers(box(x,y,x+1,y+1))}
spec=importlib.util.spec_from_file_location('old_flat_auditor',R/'author-review-r2/source-snapshot/tools/audit_source_geometry.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
old.verify_topology(source,candidate)
assert preserves_source_topology(source,cells(source),1,0,0)
positive=verify_topology(source,source)
assert not preserves_source_topology(source,cells(candidate),1,0,0)
try:verify_topology(source,candidate)
except AssertionError:rejected=True
else:raise AssertionError('nested filled hole accepted')
print(json.dumps({'scope':'predicate/auditor semantic regression; synthetic 2396-cell geometry is not a deployable 800-cell farm','source_valid':source.is_valid,'candidate_valid':candidate.is_valid,'overall_iou':source.intersection(candidate).area/source.union(candidate).area,'old_flat_hole_auditor_accepted':True,'new_candidate_predicate_rejected':True,'new_independent_auditor_rejected':True,'correct_nested_source_island_positive':positive},indent=2))
