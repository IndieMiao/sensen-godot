"""Liu Bei's warm-room adapter. Reuse accepted 172 objects; keep its source read-only."""
from pathlib import Path
import sys,json,math,hashlib,copy
import bpy
from mathutils import Matrix,Vector
import scene_room_pipeline as p
from scene_room_pipeline import cube,mesh,tube,material,v
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art/source/coffee_shop'))
import kit as k
import series_revision as sr

def bind():
    k.OUT=p.OUT;k.SOURCE=p.SOURCE;k.QA=p.QA;k.SLUG=p.SLUG
    k.KITS.clear();k.KITS.update(p.KITS);k.INSTANCES[:]=p.INSTANCES;k.PALETTE.update(p.b.PALETTE)

def delete(name):
    if name not in p.KITS:return
    rec=p.KITS.pop(name)
    for obj in list(rec['objects']):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.objects.remove(rec['root'],do_unlink=True)
    for i in list(p.INSTANCES):
        if i['asset']==name:
            root=bpy.data.objects.get(i['name'])
            if root:
                for o in list(root.children):bpy.data.objects.remove(o,do_unlink=True)
                bpy.data.objects.remove(root,do_unlink=True)
            p.INSTANCES.remove(i)

def clear(name):
    rec=p.KITS[name];p.b.CURRENT=rec
    for obj in list(rec['objects']):bpy.data.objects.remove(obj,do_unlink=True)
    rec['objects'].clear();return rec

def remove_matching(name,words):
    rec=p.KITS[name]
    for obj in list(rec['objects']):
        if any(w in obj.name.lower() for w in words):rec['objects'].remove(obj);bpy.data.objects.remove(obj,do_unlink=True)

def recolor_palette():
    p.b.MATS.clear()
    for rec in p.KITS.values():
        for obj in rec['objects']:
            for slot in obj.material_slots:
                mat=slot.material
                if not mat or any(n.type=='TEX_IMAGE' for n in mat.node_tree.nodes):continue
                key=next((q for q in sorted(p.b.PALETTE,key=len,reverse=True) if mat.name.startswith(q+'_')),None)
                if key:
                    kind=next((q for q in ('wood','cloth','plaster','metal') if '_'+q+'_' in mat.name),'matte')
                    axis=mat.name.split('_')[-1].split('.')[0];slot.material=material(key,kind,axis if axis in ('X','Y','Z') else 'X')

def move(name,at):
    rec=p.KITS[name];rec['at']=list(at);rec['root'].location=v(at)

def stretch(name,scale):
    rec=p.KITS[name];m=Matrix.Diagonal((scale[0],scale[2],scale[1],1))
    for o in rec['objects']:o.matrix_basis=m@o.matrix_basis
    for b in rec['collision']:
        b['at']=[b['at'][i]*scale[i] for i in range(3)];b['size']=[b['size'][i]*scale[i] for i in range(3)]

def sync():
    for a in p.INSTANCES:
        root=bpy.data.objects[a['name']];root.location=v(a['position']);root.rotation_euler.z=math.radians(a['yaw_degrees'])
        for o in list(root.children):bpy.data.objects.remove(o,do_unlink=True)
        for src in p.KITS[a['asset']]['objects']:
            o=src.copy();o.data=src.data;bpy.context.scene.collection.objects.link(o);o.parent=root

def bold(text,at,width,color='linen'):
    font=bpy.data.fonts.load(str(ROOT/'tools/art/source/coffee_shop/fonts/Nunito-Black.ttf'))
    curve=bpy.data.curves.new('Nunito Black '+text,'FONT');curve.font=font;curve.body=text;curve.align_x='CENTER';curve.size=.3;curve.extrude=.004;curve.resolution_u=4
    o=bpy.data.objects.new('Bold sign '+text,curve);bpy.context.scene.collection.objects.link(o);o.location=v((at[0],at[1],at[2]+.005));o.rotation_euler.x=math.pi/2
    bpy.context.view_layer.update();curve.size*=width/o.dimensions.x
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');p.b.finish(bpy.context.object,'Bold sign '+text,color);o['atlas_constant_colour']=True
    return o

def structure(width,depth,height):
    source=ROOT/'tools/art/source/standard_room_5/standard_room_5.blend';report=[]
    words=['upright oak timber','timber joint cap','post foot','heavy top beam','beam peg','wall skirting','door left skirting']
    for name,length in [('window_wall',depth),('back_wall',width)]:
        remove_matching(name,words)
        temp=p.reuse('_172_'+name,(0,0,0),source='standard_room_5',original=name)
        dest=p.KITS[name]
        for src in temp['objects']:
            low=src.name.lower()
            if not any(w in low for w in words):continue
            o=src.copy();o.data=src.data.copy();dest['collection'].objects.link(o);o.parent=dest['root'];dest['objects'].append(o);o.name='172 reused '+src.name
            span_axis=None;ratio=1
            if 'upright' in low:
                o.location.x=math.copysign(length/2-.08,o.location.x);o.location.z=height/2;span_axis=2;ratio=(height+.15)/3.5
            elif 'joint cap' in low:o.location.x=math.copysign(length/2-.08,o.location.x);o.location.z=height-.05
            elif 'post foot' in low:o.location.x=math.copysign(length/2-.08,o.location.x)
            elif 'top beam' in low:o.location.z=height-.07;span_axis=0;ratio=(length-.10)/6.1
            elif 'beam peg' in low:o.location.x*=length/6.2;o.location.z=height-.32
            else:
                o.location.x=0;span_axis=0;ratio=(length-.34)/(5.86 if 'wall skirting' in low else max(.1,max(v.co.x for v in o.data.vertices)-min(v.co.x for v in o.data.vertices)))
            before=[max(v.co[i] for v in o.data.vertices)-min(v.co[i] for v in o.data.vertices) for i in range(3)]
            if span_axis is not None:
                for vert in o.data.vertices:vert.co[span_axis]*=ratio
            after=[max(v.co[i] for v in o.data.vertices)-min(v.co[i] for v in o.data.vertices) for i in range(3)]
            bevels=[{'width':m.width,'segments':m.segments} for m in o.modifiers if m.type=='BEVEL']
            report.append({'source_collection':name,'source_object':src.name,'object':o.name,'before_blender_extent':before,'after_blender_extent':after,'length_axis':span_axis,'bevels':bevels,'cross_section_preserved':all(abs(before[i]-after[i])<1e-6 for i in range(3) if i!=span_axis)})
            assert report[-1]['cross_section_preserved']
        delete('_172_'+name)
    remove_matching('room_shell',['rounded timber foundation','floor long edging','floor end edging'])
    temp=p.reuse('_172_floor',(0,0,0),source='standard_room_5',original='room_shell');dest=p.KITS['room_shell']
    for src in temp['objects']:
        low=src.name.lower()
        if not any(w in low for w in ['rounded timber foundation','floor long edging','floor end edging']):continue
        o=src.copy();o.data=src.data.copy();dest['collection'].objects.link(o);o.parent=dest['root'];dest['objects'].append(o);o.name='172 reused '+src.name
        if 'foundation' in low:
            for vert in o.data.vertices:vert.co.x*=(width+.4)/6.6;vert.co.y*=(depth+.4)/6.6
        elif 'long edging' in low:
            o.location.x=math.copysign(width/2+.03,o.location.x)
            for vert in o.data.vertices:vert.co.y*=(depth+.35)/6.55
        else:
            o.location.y=math.copysign(depth/2+.03,o.location.y)
            for vert in o.data.vertices:vert.co.x*=width/6.2
        report.append({'source_collection':'room_shell','source_object':src.name,'object':o.name,'cross_section_preserved':True,'bevels':[{'width':m.width,'segments':m.segments} for m in o.modifiers if m.type=='BEVEL'],'adaptation':'Span lengths only; plinth thickness and edging section retained.'})
    delete('_172_floor');recolor_palette()
    result={'source':'tools/art/source/standard_room_5/standard_room_5.blend','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_revision':'accepted SGODOT-172 R2.1 ef7e48c6','parts':report,'source_read_only':True,'scope':'Only span lengths and placements adapted to existing envelope; cross sections and bevel modifiers copied.'}
    (p.SOURCE/'structure-reuse.json').write_text(json.dumps(result,indent=2)+'\n')

def add_plant(d,name,asset,at,scale=1,yaw=0,colliders=None):
    d.setdefault('shared_plants',[]).append(sr.plant(name,asset,at,scale,yaw,colliders=colliders))

def bounds(d,width,depth,entrance_x=0):
    top=.082;z=depth/2
    p.KITS['room_shell']['collision']=[{'at':[0,-.088,0],'size':[width+.4,.34,depth+.4]}, {'at':[-width/2,1.8,0],'size':[.20,3.8,depth]}, {'at':[0,1.8,-depth/2],'size':[width,3.8,.20]}]
    d['boundaries']=[{'name':'right_edge','at':[width/2+.13,.7,0],'size':[.1,1.5,depth+.3]}, {'name':'front_left_edge','at':[(-width/2+entrance_x-.52)/2,.7,z+.13],'size':[width/2+entrance_x-.52,1.5,.10]}, {'name':'front_right_edge','at':[(width/2+entrance_x+.52)/2,.7,z+.13],'size':[width/2-entrance_x-.52,1.5,.10]}, {'name':'entrance_end','at':[entrance_x,.7,z+.28],'size':[1.10,1.5,.10]}]
    return {'inside':[entrance_x,top,z-.28],'outside':[entrance_x,top,z+.025]}

def finish(d,corners,reference_size,footprint):
    report_file=p.SOURCE/'structure-reuse.json';report=json.loads(report_file.read_text())
    retained={o.name for rec in p.KITS.values() for o in rec['objects']}
    for part in report['parts']:part['retained']=part['object'] in retained
    report_file.write_text(json.dumps(report,indent=2)+'\n')
    sync();bind()
    from liubei_r2 import fit_camera
    fit_camera(d,reference_size,corners,footprint)
    d.setdefault('revision','R2');d.setdefault('shared_plants',[]);d.setdefault('material_overrides',{});d.setdefault('botanical_assets',[])
    p.MANIFEST_EXTRA.update(d)
    p.finalize(d['camera'],d['review_lighting'])
    # Include the same shared editable plant source instances without flattening them.
    bind();layout=json.loads((p.OUT/'layout.json').read_text());sr.append_plants(layout)
    if '--geometry-only' not in sys.argv:
        k.bake_and_export(ao_strength=.56,ao_distance=.42,coherent_swatches=True)
        from series_batch import build
        build(p.SLUG)
        layout_file=p.OUT/'layout.json';layout=json.loads(layout_file.read_text())
        for batch in layout['render_batches']:
            if batch['material']=='plants':batch['cast_shadow']=False
        layout_file.write_text(json.dumps(layout,indent=2)+'\n')
        stats_file=p.OUT/'asset_stats.json';stats=json.loads(stats_file.read_text())
        stats['scene_budget']['render_batches']=layout['render_batches'];stats_file.write_text(json.dumps(stats,indent=2)+'\n')
