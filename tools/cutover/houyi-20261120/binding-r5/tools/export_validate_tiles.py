import pathlib,json,sqlite3,gzip,hashlib,collections,time,importlib.metadata
from mapbox_vector_tile.Mapbox import vector_tile_pb2
R=pathlib.Path(__file__).resolve().parents[1];out=R/'generated';m=json.loads((R/'staging/manifest-before-tiles.json').read_text());catalog=json.loads((out/'parcel-catalog.json').read_text())['parcels'];expected={p['block_id'] for p in catalog};byid={p['block_id']:p for p in catalog};byzoom=collections.defaultdict(set);counts=collections.Counter();sizes=collections.defaultdict(list);files=m['files'];t=time.monotonic()
conn=sqlite3.connect(str(R/'staging/parcels.mbtiles'));metadata=dict(conn.execute('select name,value from metadata'));errors=[]
for z,x,tms,b in conn.execute('select zoom_level,tile_column,tile_row,tile_data from tiles order by zoom_level,tile_column,tile_row'):
 y=(1<<z)-1-tms;raw=gzip.decompress(b) if b[:2]==b'\x1f\x8b' else b;tile=vector_tile_pb2.tile();tile.ParseFromString(raw)
 assert tile.layers and all(layer.name=='parcels' for layer in tile.layers),(z,x,y)
 for layer in tile.layers:
  keys=list(layer.keys)
  for f in layer.features:
   attrs={}
   for i in range(0,len(f.tags),2):
    key=keys[f.tags[i]];value=layer.values[f.tags[i+1]]
    if value.HasField('string_value'):attrs[key]=value.string_value
    elif value.HasField('int_value'):attrs[key]=value.int_value
    elif value.HasField('double_value'):attrs[key]=value.double_value
    elif value.HasField('float_value'):attrs[key]=value.float_value
    elif value.HasField('uint_value'):attrs[key]=value.uint_value
    elif value.HasField('sint_value'):attrs[key]=value.sint_value
   pid=attrs.get('block_id');assert pid in expected,(z,x,y,pid)
   assert attrs.get('farm_path')=='farms/'+pid+'.json'
   assert 'parcel_id' in attrs and 'center_lon' in attrs and 'center_lat' in attrs
   assert f.type==3 and f.geometry,'nonpolygon/empty tile feature'
   expected_row=byid[pid]
   for key in ['parcel_id','name','address','core_cell_count','extension_cell_count','total_cell_count','cell_count']:
    assert attrs.get(key)==(expected_row[key] if expected_row[key] is not None else ''),(z,pid,key,attrs.get(key),expected_row[key])
   assert attrs['cell_count']==attrs['core_cell_count'] and attrs['core_cell_count']+attrs['extension_cell_count']==attrs['total_cell_count']
   byzoom[z].add(pid);counts[z]+=1
 rel=f'tiles/{z}/{x}/{y}.pbf';p=out/rel;p.parent.mkdir(parents=True,exist_ok=True)
 encoded=b if b[:2]==b'\x1f\x8b' else gzip.compress(b,mtime=0);p.write_bytes(encoded);files[rel]=hashlib.sha256(encoded).hexdigest();sizes[z].append(len(encoded))
summary={'tippecanoe_version':'2.79.0','source_layer':'parcels','input_parcels':len(expected),'gzip':True,'xyz_export_from_mbtiles_tms':True,'parameters':['-Z15','-z18','-r1','--no-feature-limit','--no-tile-size-limit','--no-tiny-polygon-reduction','--full-detail=12','--low-detail=12','--simplification=1','--buffer=5'],'zooms':{},'metadata':metadata,'decode_seconds':time.monotonic()-t}
for z in sorted(byzoom):
 missing=sorted(expected-byzoom[z]);summary['zooms'][str(z)]={'unique_parcels':len(byzoom[z]),'missing_count':len(missing),'missing_ids':missing,'feature_instances_with_tile_duplication':counts[z],'tile_count':len(sizes[z]),'compressed_bytes':sum(sizes[z]),'max_compressed_tile_bytes':max(sizes[z]),'simplification':'tippecanoe simplification1/detail12; input geographic geometry pre-simplified0.0000003 degree; not an empirical per-feature removed-vertex count','drop_policy':'no intentional density/size dropping; missing list measures quantization/simplification fallout'}
(R/'evidence/mvt-validation.json').write_text(json.dumps(summary,indent=2)+'\n')
assert len(byzoom[18])==len(expected),'maxzoom has missing IDs; do not freeze'
p=out/'reports/mvt-validation.json';p.write_text(json.dumps(summary,indent=2)+'\n');files['reports/mvt-validation.json']=hashlib.sha256(p.read_bytes()).hexdigest()
m['mvt_validation']={z:{k:v for k,v in d.items() if k!='missing_ids'} for z,d in summary['zooms'].items()};m['files']=files
(R/'staging/manifest-after-tiles.json').write_text(json.dumps(m,separators=(',',':'))+'\n');print('MVT_READY',len(expected),'tiles',sum(map(len,sizes.values())),'manifest',hashlib.sha256((R/'staging/manifest-after-tiles.json').read_bytes()).hexdigest(),flush=True)
