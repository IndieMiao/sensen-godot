"""Liu Bei shared botanical kit. Godot metres, Y-up, local pot-base / vine-top pivots.
blender --background --factory-startup --python "$PWD/assets/rooms/_shared/plants/source/build_plants.py"
"""
from pathlib import Path
import sys, math, random, json
ROOT=Path(__file__).resolve().parents[5]
sys.path.insert(0,str(ROOT/'tools/art/source/coffee_shop'))
import kit as k
from mathutils import Vector

GREENS=['789454','859F61','99AD6E','668547','A9B67D','789158']

def blade(name,a,b,width,color,split=False,seed=0):
    """Closed curved leaf with lobed silhouette, central ridge and raised pale veins."""
    rng=random.Random(seed);a=Vector(a);b=Vector(b);d=(b-a).normalized()
    normal=Vector((.28,.65,1.0));normal=(normal-d*normal.dot(d)).normalized()
    side=d.cross(normal)
    if side.length<.1:side=d.cross(Vector((1,0,0)))
    side.normalize();normal=side.cross(d).normalized()
    if normal.y<0:normal=-normal
    steps=32 if split else 10
    vs=[];faces=[]
    for layer in (0,1):
        for i in range(steps+1):
            t=i/steps;mid=a.lerp(b,t)+normal*(math.sin(t*math.pi)*width*.22)
            for s in (-1,0,1):
                shape=math.sin(math.pi*t)**.70
                if split and 8<=i<=28:
                    # Narrow open sinuses reach towards the midrib, never disconnected cards.
                    shape*= (.30 if i+(0 if s<0 else 1) in (11,19,27) else .82 if i+(0 if s<0 else 1) in (10,12,18,20,26,28) else 1)
                w=max(.002,shape*width*.5)
                vs.append(mid+side*(s*w)+normal*(-abs(s)*width*.13*math.sin(t*math.pi)-layer*.007))
    n=(steps+1)*3
    for layer in range(2):
        for i in range(steps):
            for j in range(2):
                q=layer*n+i*3+j;faces.append((q,q+1,q+4,q+3))
    border=[i*3 for i in range(steps+1)]+[steps*3+1]+[i*3+2 for i in reversed(range(steps+1))]+[1]
    for i,u in enumerate(border):
        v=border[(i+1)%len(border)];faces.append((u,v,v+n,u+n))
    obj=k.mesh(name,vs,faces,color,smooth=True)
    # Veins are surface detail, baked from explicit source UVs into the shared atlas.
    uv=obj.data.uv_layers.new(name='LeafDetailUV')
    for face in obj.data.polygons:
        for li in face.loop_indices:
            vi=obj.data.loops[li].vertex_index%n
            uv.data[li].uv=((vi%3)/2,(vi//3)/steps)
    mat=k.material(color,'leaf')
    if not mat.get('painted_veins'):
        nt=mat.node_tree;p=nt.nodes.get('Principled BSDF')
        tex=nt.nodes.new('ShaderNodeUVMap');tex.uv_map='LeafDetailUV'
        sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(tex.outputs['UV'],sep.inputs[0])
        sub=nt.nodes.new('ShaderNodeMath');sub.operation='SUBTRACT';sub.inputs[1].default_value=.5;nt.links.new(sep.outputs['X'],sub.inputs[0])
        ab=nt.nodes.new('ShaderNodeMath');ab.operation='ABSOLUTE';nt.links.new(sub.outputs[0],ab.inputs[0])
        mid=nt.nodes.new('ShaderNodeMath');mid.operation='LESS_THAN';mid.inputs[1].default_value=.026;nt.links.new(ab.outputs[0],mid.inputs[0])
        mul=nt.nodes.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=6;nt.links.new(sep.outputs['Y'],mul.inputs[0])
        add=nt.nodes.new('ShaderNodeMath');add.operation='ADD';nt.links.new(mul.outputs[0],add.inputs[0]);nt.links.new(ab.outputs[0],add.inputs[1])
        fract=nt.nodes.new('ShaderNodeMath');fract.operation='FRACT';nt.links.new(add.outputs[0],fract.inputs[0])
        thin=nt.nodes.new('ShaderNodeMath');thin.operation='LESS_THAN';thin.inputs[1].default_value=.045;nt.links.new(fract.outputs[0],thin.inputs[0])
        maximum=nt.nodes.new('ShaderNodeMath');maximum.operation='MAXIMUM';nt.links.new(mid.outputs[0],maximum.inputs[0]);nt.links.new(thin.outputs[0],maximum.inputs[1])
        mix=nt.nodes.new('ShaderNodeMixRGB');nt.links.new(maximum.outputs[0],mix.inputs[0]);mix.inputs[1].default_value=(*k.rgb(color),1);mix.inputs[2].default_value=(*k.rgb('9CAF77'),1);nt.links.new(mix.outputs[0],p.inputs['Base Color'])
        mat['painted_veins']=True
    obj.data.materials.clear();obj.data.materials.append(mat)
    return obj

def pot(radius=.25,height=.48,woven=False):
    k.lathe('Rounded ceramic planter',(0,0,0),[(0,radius*.67),(.05,radius*.8),(height*.78,radius),(height,radius*.94),(height,radius*.84),(height-.05,radius*.83)],'D8CAB0',24,'plaster')
    k.cylinder('Rich potting soil',(0,height-.055,0),radius*.83,.018,'554837',vertices=20)
    if woven:
        for i in range(10):
            h=.045+i*(height-.09)/10;r=radius*(.8+.17*math.sin(h/height*math.pi/2))
            k.tube('Wicker horizontal binding',[(r*math.cos(j*math.tau/32),h,r*math.sin(j*math.tau/32)) for j in range(33)],.010,'B5A383',5)
        for i in range(24):
            a=i*math.tau/24;k.tube('Wicker upright',[(math.cos(a)*radius*.78,.05,math.sin(a)*radius*.78),(math.cos(a)*radius*.98,height*.87,math.sin(a)*radius*.98)],.007,'C4B493',5)
    else:
        for i in range(20):
            a=i*math.tau/20
            k.tube('Soft ceramic rib',[(math.cos(a)*radius*.78,.06,math.sin(a)*radius*.78),(math.cos(a)*radius*.985,height*.78,math.sin(a)*radius*.985)],.006,'E6D9C3',5)

def monstera(seed=3):
    pot(.33,.57)
    rng=random.Random(seed)
    for i in range(11):
        a=i*2.399+rng.uniform(-.18,.18);h=.72+(i%4)*.23
        root=(rng.uniform(-.08,.08),.51,rng.uniform(-.06,.06))
        start=(math.cos(a)*.29,h,math.sin(a)*.24)
        end=(start[0]+math.cos(a)*.23,h+(.39 if i%3 else -.22),start[2]+(.18 if i%3 else .38))
        k.tube('Monstera arched petiole',[root,(start[0]*.7,h-.18,start[2]*.7),start],.010,GREENS[3],6)
        blade('Monstera split leaf %02d'%i,start,end,.43+(i%3)*.045,GREENS[i%6],True,i)

def peace_lily():
    pot(.245,.39)
    for i in range(15):
        a=i*2.399;h=.68+(i%3)*.075
        blade('Peace lily leaf',(0,.33,0),(math.cos(a)*.43,h,math.sin(a)*.37),.18,GREENS[i%6],seed=i)
    for i in range(4):
        x=(i-1.5)*.11;z=math.sin(i*3)*.15;y=.96+(i%2)*.17
        k.tube('White spathe stem',[(0,.35,0),(x*.5,.78,z),(x,y,z)],.008,GREENS[1],5)
        blade('Ivory peace lily spathe',(x,y-.08,z),(x+.05,y+.22,z-.10),.18,'F4F0D9',seed=i)
        k.ellipsoid('Golden spadix',(x+.018,y+.06,z+.025),(.026,.13,.025),'E3C879',10,6)

def vine(length=.9,seed=7,flowers=True):
    rng=random.Random(seed);steps=round(length/.055)
    path=[(math.sin(j*.62+seed)*.035,-j*length/steps,math.sin(j*.43)*.035) for j in range(steps+1)]
    k.tube('Flexible living stem',path,.009,GREENS[3],6)
    for j,p in enumerate(path):
        for s in (-1,1):
            end=(p[0]+s*rng.uniform(.12,.23),p[1]+rng.uniform(-.10,.09),p[2]+rng.uniform(.03,.14))
            blade('Curled ivy leaf',p,end,rng.uniform(.10,.15),GREENS[(j+(0 if s<0 else 2))%6],seed=j+seed)
        if flowers and j%3==seed%3:
            for f in range(2 if j%2==0 else 1):
                k.flower((p[0]+rng.uniform(-.10,.11),p[1]+.04,p[2]+.14+f*.025),rng.uniform(.72,1.12))

def pothos():
    pot(.20,.30,woven=True)
    for i in range(4):
        before=len(k.CURRENT['objects']);vine(.55+i*.15,22+i,False)
        for o in k.CURRENT['objects'][before:]:o.location+=k.v((math.cos(i*1.7)*.14,.31,math.sin(i*1.7)*.14))
    for i in range(8):
        a=i*2.399;blade('Pothos crown',(0,.27,0),(math.cos(a)*.26,.43,math.sin(a)*.26),.14,GREENS[i%6],seed=i)

def shrub():
    rng=random.Random(44)
    for i in range(25):
        a=i*2.399;r=.12+.26*math.sqrt(i/25)
        start=(math.cos(a)*r*.5,0,math.sin(a)*r*.5);end=(math.cos(a)*r,.16+rng.random()*.18,math.sin(a)*r)
        k.tube('Shrub twig',[start,end],.008,GREENS[3],5)
        for j in range(3):
            ang=a+j*2.3
            blade('Shrub cup leaf',end,(end[0]+math.cos(ang)*.17,end[1]+.075,end[2]+math.sin(ang)*.17),.115,GREENS[(i+j)%6],seed=i+j)
        if i%2==0:k.flower((end[0],end[1]+.12,end[2]),1.2)

def olive():
    pot(.30,.53)
    k.tube('Olive trunk',[(0,.43,0),(.04,.90,.02),(-.02,1.3,.01),(.06,1.9,0)],.04,'8C7754',7)
    for i in range(16):
        a=i*2.399;h=.87+(i%5)*.19;p=(math.cos(a)*.38,h+.20,math.sin(a)*.37)
        k.tube('Olive branch',[(0,h-.2,0),p],.014,'8C7754',5)
        for j in range(6):
            s=-1 if j%2 else 1;q=(p[0]+s*.12,p[1]+j*.025,p[2]+math.sin(j*2)*.11)
            blade('Silver olive leaf',p,q,.04,['899779','ADB594','768969'][j%3],seed=j)

def fruit_tree():
    pot(.42,.55)
    k.tube('Fruit tree split trunk',[(0,.5,0),(.04,1.05,.02),(-.08,1.50,0)],.06,'846649',8)
    rng=random.Random(39)
    for c in range(7):
        a=c*2.399;center=(math.cos(a)*.30,1.45+(c%3)*.20,math.sin(a)*.30)
        k.tube('Fruit tree branch',[(0,1.0,0),center],.027,'846649',6)
        for j in range(13):
            a=j*2.399+c;end=(center[0]+math.cos(a)*.31,center[1]+rng.uniform(-.12,.29),center[2]+math.sin(a)*.31)
            blade('Fruit canopy leaf',center,end,.15,GREENS[(j+c)%6],seed=j+c)
        pos=(center[0]*1.65,center[1]-.13,center[2]*1.65)
        k.ellipsoid('Ripe orange',pos,(.15,.15,.15),'E9A04A',12,8)
        k.leaf('Orange leaf',(pos[0],pos[1]+.075,pos[2]),(pos[0]+.10,pos[1]+.10,pos[2]),.05,GREENS[0])

def build():
    k.configure('_shared/plants',source=Path(__file__).resolve().parent);k.SLUG='plants'
    k.bpy.context.preferences.filepaths.save_version=0
    for i,(name,fn) in enumerate([('monstera',monstera),('peace_lily',peace_lily),('pothos',pothos),('ivy_short',lambda:vine(.65,11)),('ivy_medium',lambda:vine(1.0,12)),('ivy_long',lambda:vine(1.4,13)),('flower_shrub',shrub),('olive_tree',olive),('fruit_tree',fruit_tree)]):
        k.begin(name,at=((i%3-1)*2.2,0,(i//3-1)*2.2));fn()
    k.save('545:2956',{'position':[8,6,10],'target':[0,.7,0],'size':9})
    k.bake_and_export(.40,.18)
    data=json.loads((k.OUT/'layout.json').read_text());data['library']=True
    for a in data['assets']:a['position']=[0,0,0]
    (k.OUT/'layout.json').write_text(json.dumps(data,indent=2)+'\n')
if __name__=='__main__':build()
