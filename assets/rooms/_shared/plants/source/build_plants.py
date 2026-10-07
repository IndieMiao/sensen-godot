"""R2 botanical kit: open curved leaves, explicit padded detail UVs, local pivots."""
from pathlib import Path
import sys,math,random,json
ROOT=Path(__file__).resolve().parents[5]
sys.path.insert(0,str(ROOT/'tools/art/source/coffee_shop'))
import kit as k
from mathutils import Vector
GREENS=['4F713F','5B7C49','678855','426133','6C8F5A','486A3F']
LEAF_COSTS=[]

def blade(name,a,b,width,color,split=False,seed=0):
    """One open leaf, at most eight triangles; Monstera cuts use the scissor atlas."""
    a=Vector(a);b=Vector(b);direction=(b-a).normalized()
    normal=Vector((.17+math.sin(seed)*.25,.85,.52));normal=(normal-direction*normal.dot(direction)).normalized()
    side=direction.cross(normal).normalized();normal=side.cross(direction).normalized()
    if normal.y<0:normal=-normal
    if split:
        # A curved 3x3 patch (8 tris) carries a lobed scissor silhouette in its tile.
        outline=[(s,t) for t in (0,.5,1) for s in (-.5,0,.5)]
        faces=[(j*3+i,j*3+i+1,(j+1)*3+i+1,(j+1)*3+i) for j in range(2) for i in range(2)]
    else:
        outline=[(0,0),(-.39,.23),(-.50,.55),(-.29,.83),(0,1),(.30,.83),(.50,.55),(.39,.23)]
        faces=[tuple(range(len(outline)))]
    verts=[a.lerp(b,t)+side*(s*width)+normal*(math.sin(t*math.pi)*width*(.17-.35*abs(s))) for s,t in outline]
    obj=k.mesh(name,verts,faces,color,'split_leaf' if split else 'leaf',True)
    obj.data.normals_split_custom_set([k.v(normal)]*len(obj.data.loops))
    uv=obj.data.uv_layers.new(name='LeafDetailUV')
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            s,t=outline[obj.data.loops[li].vertex_index];uv.data[li].uv=(s+.5,t)
    obj['botanical_leaf']=True
    obj.data.calc_loop_triangles();LEAF_COSTS.append(len(obj.data.loop_triangles));assert LEAF_COSTS[-1]<=8
    return obj

def flower(at,scale=1,seed=0):
    # Five spoon petals, six triangles each, plus a low-poly pollen centre.
    x,y,z=at
    for j in range(5):
        a=j*math.tau/5+seed*.3
        blade('Small ivory petal',(x,y,z),(x+math.cos(a)*.042*scale,y+.009*scale,z+math.sin(a)*.042*scale),.032*scale,'FFFEF5',seed=j)
    rr=.0115*scale;hh=.0065*scale;cy=y+.008*scale
    k.mesh('Eight-triangle daisy centre',[(x+rr,cy,z),(x,cy,z+rr),(x-rr,cy,z),(x,cy,z-rr),(x,cy+hh,z),(x,cy-hh,z)],[(i,(i+1)%4,4) for i in range(4)]+[((i+1)%4,i,5) for i in range(4)],'D9AC4C')

def pot(radius=.25,height=.48,style='ceramic'):
    color={'ceramic':'E6CEA6','terra':'C68150','woven':'C5A16C'}[style]
    obj=k.lathe(style.title()+' planter',(0,0,0),[(0,radius*.69),(.05,radius*.8),(height*.78,radius),(height,radius*.94),(height,radius*.84),(height-.05,radius*.83)],color,24,'woven' if style=='woven' else 'matte')
    obj['cylindrical_uv_height']=height
    k.cylinder('Potting soil',(0,height-.055,0),radius*.83,.018,'736040',vertices=16)
    if style=='woven':
        for h in (.045,height*.93):
            r=radius*(.80 if h<height*.5 else .96)
            k.tube('Wicker bound rim',[(r*math.cos(j*math.tau/24),h,r*math.sin(j*math.tau/24)) for j in range(25)],.012,'AD8756',5)
    elif style=='terra':
        lip=k.lathe('Terracotta rolled lip',(0,height-.055,0),[(0,radius*.97),(.03,radius*1.025),(.075,radius*.98)],'D69361',24)
        bm=k.bmesh.new();bm.from_mesh(lip.data)
        k.bmesh.ops.delete(bm,geom=[f for f in bm.faces if len(f.verts)>4],context='FACES_ONLY')
        bm.to_mesh(lip.data);bm.free()
    else:
        for i in range(16):
            a=i*math.tau/16
            k.tube('Soft ceramic flute',[(math.cos(a)*radius*.80,.06,math.sin(a)*radius*.80),(math.cos(a)*radius*.983,height*.77,math.sin(a)*radius*.983)],.004,'EDDCBC',4)

def monstera(style='ceramic'):
    pot(.33,.57,style)
    rng=random.Random(3)
    for i in range(11):
        angle=i*2.399+rng.uniform(-.16,.16);h=.72+(i%4)*.23
        start=(math.cos(angle)*.29,h,math.sin(angle)*.24)
        end=(start[0]+math.cos(angle)*.29,h+(.34 if i%3 else -.21),start[2]+(.28 if i%3 else .39))
        k.tube('Monstera petiole',[(rng.uniform(-.07,.07),.51,0),(start[0]*.7,h-.18,start[2]*.7),start],.009,GREENS[3],5)
        blade('Monstera deeply split leaf %02d'%i,start,end,.47+(i%3)*.045,GREENS[i%6],True,i)

def peace_lily():
    pot(.245,.39)
    for i in range(15):
        a=i*2.399
        blade('Peace lily leaf',(0,.33,0),(math.cos(a)*.43,.68+(i%3)*.075,math.sin(a)*.37),.18,GREENS[i%6],seed=i)
    for i in range(4):
        x=(i-1.5)*.11;z=math.sin(i*3)*.15;y=.96+(i%2)*.17
        k.tube('Spathe stem',[(0,.35,0),(x*.5,.78,z),(x,y,z)],.006,GREENS[1],5)
        blade('Small ivory spathe',(x,y-.04,z),(x+.025,y+.11,z-.05),.09,'FFF2CF',seed=i)
        k.ellipsoid('Gold spadix',(x+.009,y+.03,z+.013),(.018,.066,.018),'E4C369',8,4)

def vine(length=.9,seed=7,flowers=True):
    rng=random.Random(seed);steps=round(length/.057)
    path=[(math.sin(j*.62+seed)*.028,-j*length/steps,math.sin(j*.43)*.025) for j in range(steps+1)]
    k.tube('Flexible attached vine stem',path,.006,GREENS[3],4)
    for j,p in enumerate(path):
        for s in (-1,1):
            end=(p[0]+s*rng.uniform(.072,.138),p[1]+rng.uniform(-.060,.054),p[2]+rng.uniform(.018,.084))
            blade('Small curved ivy leaf',p,end,rng.uniform(.060,.090),GREENS[(j+(0 if s<0 else 2))%6],seed=j+seed)
        if flowers:
            flower((p[0]+rng.uniform(-.07,.07),p[1]+.02,p[2]+.065),rng.uniform(1.05,1.57),j)

def pothos():
    pot(.20,.30,'woven')
    for i in range(4):
        before=len(k.CURRENT['objects']);vine(.55+i*.15,22+i,False)
        for o in k.CURRENT['objects'][before:]:o.location+=k.v((math.cos(i*1.7)*.14,.31,math.sin(i*1.7)*.14))
    for i in range(8):
        a=i*2.399;blade('Pothos crown',(0,.27,0),(math.cos(a)*.156,.366,math.sin(a)*.156),.084,GREENS[i%6],seed=i)

def shrub():
    rng=random.Random(44)
    for i in range(56):
        a=i*2.399;r=.44*math.sqrt((i+.5)/56)
        end=(math.cos(a)*r,.055+.28*math.sqrt(max(0,1-(r/.46)**2))+rng.uniform(-.02,.02),math.sin(a)*r)
        # Overlapping tiers hide the branches, forming a hemispherical cushion.
        for j in range(5):
            angle=a+j*2.3
            blade('Small shrub leaf',end,(end[0]+math.cos(angle)*.13,end[1]+.015,end[2]+math.sin(angle)*.13),.10,GREENS[(i+j)%6],seed=i+j)
        if i%3==0:flower((end[0],end[1]+.035,end[2]),1.40,i)

def olive():
    pot(.30,.53,'terra')
    k.tube('Olive trunk',[(0,.43,0),(.04,.90,.02),(-.02,1.3,.01),(.06,1.9,0)],.038,'997C54',7)
    rng=random.Random(12)
    for i in range(22):
        a=i*2.399;h=.97+(i%5)*.17;p=(math.cos(a)*.30,h+.18,math.sin(a)*.30)
        k.tube('Olive woody branch',[(0,h-.18,0),p],.011,'997C54',4)
        for j in range(16):
            angle=j*2.399+i;start=(p[0]+math.cos(angle)*.09,p[1]+rng.uniform(-.07,.12),p[2]+math.sin(angle)*.09)
            end=(start[0]+math.cos(angle)*.16,start[1]+.06,start[2]+math.sin(angle)*.16)
            blade('Silver olive leaf',start,end,.046,['59744F','64805A','49683E','6F8961'][j%4],seed=j+i)

def fruit_tree():
    pot(.42,.55,'terra')
    k.tube('Forked fruit trunk',[(0,.5,0),(.04,1.05,.02),(-.08,1.50,0)],.06,'967343',7)
    rng=random.Random(39)
    for c in range(7):
        a=c*2.399;center=(math.cos(a)*.30,1.45+(c%3)*.20,math.sin(a)*.30)
        k.tube('Fruit branch',[(0,1.0,0),center],.022,'967343',5)
        for j in range(26):
            a=j*2.399+c;start=(center[0]+math.cos(a)*.13,center[1]+rng.uniform(-.10,.16),center[2]+math.sin(a)*.13)
            blade('Fruit canopy leaf',start,(start[0]+math.cos(a)*.18,start[1]+.10,start[2]+math.sin(a)*.18),.11,GREENS[(j+c)%6],seed=j+c)
        pos=(center[0]*1.65,center[1]-.13,center[2]*1.65)
        k.ellipsoid('Ripe orange',pos,(.16,.16,.16),'EAA040',10,6)
        blade('Orange twig leaf',(pos[0],pos[1]+.075,pos[2]),(pos[0]+.09,pos[1]+.10,pos[2]),.045,GREENS[0])

def build():
    k.configure('_shared/plants',source=Path(__file__).resolve().parent);k.SLUG='plants'
    k.bpy.context.preferences.filepaths.save_version=0
    modules=[('monstera',monstera),('monstera_woven',lambda:monstera('woven')),('peace_lily',peace_lily),('pothos',pothos),('ivy_short',lambda:vine(.65,11)),('ivy_medium',lambda:vine(1,12)),('ivy_long',lambda:vine(1.4,13)),('flower_shrub',shrub),('olive_tree',olive),('fruit_tree',fruit_tree),('pot_terracotta',lambda:pot(.30,.53,'terra')),('pot_woven',lambda:pot(.33,.57,'woven'))]
    for i,(name,fn) in enumerate(modules):
        k.begin(name,at=((i%4-1.5)*2.2,0,(i//4-1)*2.2));fn()
    k.save('545:2956',{'position':[8,6,10],'target':[0,.7,0],'size':11})
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from export_atlas import export
    export()
    data=json.loads((k.OUT/'layout.json').read_text());data['library']=True;data['revision']='R2.1'
    for a in data['assets']:a['position']=[0,0,0]
    (k.OUT/'layout.json').write_text(json.dumps(data,indent=2)+'\n')
    stats=json.loads((k.OUT/'asset_stats.json').read_text())
    prev={'monstera':5344,'peace_lily':3616,'pothos':21092,'ivy_short':5784,'ivy_medium':9312,'ivy_long':11956,'flower_shrub':14992,'olive_tree':13276,'fruit_tree':14248}
    stats['r1_comparison']={a['name']:{'before':prev.get(a['name'],0),'after':a['triangles']} for a in stats['assets']}
    stats['leaf_triangle_max']=max(LEAF_COSTS);stats['leaf_count']=len(LEAF_COSTS)
    assert next(a['triangles'] for a in stats['assets'] if a['name']=='flower_shrub')<=4000
    (k.OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    k.bpy.ops.wm.save_as_mainfile(filepath=str(k.SOURCE/'plants.blend'))
if __name__=='__main__':build()
