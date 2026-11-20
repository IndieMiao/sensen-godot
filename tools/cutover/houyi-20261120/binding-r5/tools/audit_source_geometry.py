"""Reconstruct emitted core RLE in projected source coordinates; never trusts claimed IoU.
No imports from generator or validate_farm. Use --ids for bounded early checks.
"""
from pathlib import Path
import argparse,gzip,json,hashlib,time,math
from audit_binding import context,bound_row,sha
import shapely
from shapely.geometry import shape
from shapely.affinity import rotate,affine_transform
from pyproj import Transformer
R=Path(__file__).resolve().parents[1]
def polygons(g):
 if g.geom_type=='Polygon':return [g]
 return [p for part in getattr(g,'geoms',[]) for p in polygons(part)]
def verify_topology(source,core):
 # Independent source-aware matching on emitted RLE; parent-local holes and
 # actual empty space prevent a nested core island from masquerading as void.
 from shapely.geometry import Polygon
 srcs=polygons(source);dsts=polygons(core)
 if len(srcs)==1 and not srcs[0].interiors:
  retained=source.intersection(core).area/source.area
  assert retained>=.85,('single_source_coverage_lost',retained)
  return {'parts':{'source_count':1,'core_count':len(dsts),'min_retained_fraction':retained,'single_source_raster_fragments_allowed':True},'holes':{'source_count':0,'core_count':sum(len(p.interiors) for p in dsts),'min_retained_fraction':1},'holes_matched_within_parent':True,'hole_coverage_uses_actual_empty_space':True}
 def match_all(left,right):
  coverage=[[s.intersection(d).area/s.area for d in right] for s in left]
  edges=[[j for j,v in enumerate(row) if v>=.85] for row in coverage];matches={}
  def augment(i,seen):
   for j in edges[i]:
    if j in seen:continue
    seen.add(j)
    if j not in matches or augment(matches[j],seen):matches[j]=i;return True
   return False
  assert all(augment(i,set()) for i in range(len(left))),('source_topology_lost',coverage)
  return {i:j for j,i in matches.items()},min((max(x) for x in coverage),default=1)
 parents,part_min=match_all(srcs,dsts);hole_min=1;hole_count=0
 for i,j in parents.items():
  left=[Polygon(r).difference(source) for r in srcs[i].interiors];left=[g for g in left if not g.is_empty]
  right=[Polygon(r).difference(core) for r in dsts[j].interiors];right=[g for g in right if not g.is_empty]
  _,retained=match_all(left,right);hole_min=min(hole_min,retained);hole_count+=len(left)
 return {'parts':{'source_count':len(srcs),'core_count':len(dsts),'min_retained_fraction':part_min},'holes':{'source_count':hole_count,'core_count':sum(len(p.interiors) for p in dsts),'min_retained_fraction':hole_min},'holes_matched_within_parent':True,'hole_coverage_uses_actual_empty_space':True}

def audit(row,f):
 g=shapely.transform(shape(row['geometry']),PROJECT.transform,interleaved=False)
 if not g.is_valid:g=shapely.make_valid(g)
 g=shapely.union_all(polygons(g));assert g.is_valid and not g.is_empty
 h=f['source_cell_m'];tr=f['source_transform'];assert h>0 and math.isfinite(h)
 rotated=rotate(g,tr['rotation_deg'],origin=g.centroid)
 sx,sy=tr['origin_m'];normalized=affine_transform(rotated,[1/h,0,0,1/h,-sx/h,-sy/h])
 ox,oy=f['grid']['origin_cell'];runs=f['zones']['core']['runs']
 boxes=[shapely.box(x+ox,y+oy,x+ox+n,y+oy+1) for y,x,n,_ in runs];core=shapely.union_all(boxes)
 assert core.is_valid and abs(core.area-f['counts']['core_cell_count'])<1e-8,'RLE geometry/count'
 intersection=normalized.intersection(core).area;iou=intersection/(normalized.area+core.area-intersection)
 assert abs(g.area-f['source_area_m2'])<max(1e-5,g.area*1e-9),'source area mismatch'
 assert abs(iou-f['stats']['core_iou'])<1e-7,(f['block_id'],'IoU mismatch',iou,f['stats']['core_iou'])
 assert iou>=.85
 topology=verify_topology(normalized,core)
 assert iou>=.9 or 'approximation_warning' in f['stats']['recovery_flags']
 # Provenance hash is of the raw geographic geometry, before repair.
 raw_hash=hashlib.sha256(json.dumps(row['geometry'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
 assert raw_hash==row['source_geometry_hash']==f['source_geometry_hash'],'source geometry hash mismatch'
 return {'block_id':f['block_id'],'source_geometry_hash':raw_hash,'measured_iou':iou,'source_polygon_count':len(polygons(g)),'source_hole_count':sum(len(p.interiors) for p in polygons(g)),'source_area_m2':g.area,'rotation_deg':tr['rotation_deg'],'topology':topology}
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--ids',nargs='*');parser.add_argument('--shard',type=int,default=0);parser.add_argument('--shards',type=int,default=1);args=parser.parse_args();PROJECT=Transformer.from_crs(4326,32610,always_xy=True)
 source_blob=(R/'audit/source-candidates.json.gz').read_bytes();manifest_blob=(R/'generated/manifest.json').read_bytes();included_blob=(R/'generated/included-parcels.json').read_bytes()
 binding=context(R,manifest_blob,included_blob,source_blob);m=json.loads(manifest_blob);rows=json.loads(gzip.decompress(source_blob));included=set(json.loads(included_blob)['block_ids'])
 rows=[x for x in rows if ('p-'+x['parcel_id']) in included and (not args.ids or x['parcel_id'] in args.ids)]
 rows=rows[args.shard::args.shards];results=[];start=time.monotonic()
 for i,row in enumerate(rows):
  path='farms/p-'+row['parcel_id']+'.json';blob=(R/'generated'/path).read_bytes();assert sha(blob)==m['files'][path],'farm differs from frozen input manifest';f=json.loads(blob)
  try:results.append({**audit(row,f),**bound_row(blob,row,f,binding)})
  except AssertionError:
   print('SOURCE_AUDIT_FAILED',f['block_id'],flush=True);raise
  if i%10000==0:print('SOURCE_AUDIT',i+1,'seconds',round(time.monotonic()-start,2),flush=True)
 assert context(R,manifest_blob,included_blob,source_blob)==binding,'auditor changed during run'
 result={'binding':binding,'scope':'bounded_ids' if args.ids else 'all_included_partition','shard':args.shard,'shards':args.shards,'count':len(results),'seconds':time.monotonic()-start,'source_candidates_sha256':sha(source_blob),'max_claimed_iou_delta_tolerance':1e-7,'results':results}
 path=R/'evidence'/('source-geometry-early.json' if args.ids else f'source-geometry-{args.shard}.json');path.write_text(json.dumps(result,separators=(',',':'))+'\n');print('SOURCE_AUDIT_DONE',len(results),result['seconds'],flush=True)
