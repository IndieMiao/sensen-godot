"""Opt-in Liu Bei R2 lettering and orthographic plinth registration.
No benchmark, gameplay camera or Zhao Yun generators are changed.
"""
import math,json
from pathlib import Path
import kit as k

def enable_lettering():
    font=k.bpy.data.fonts.load(str(Path(__file__).with_name('fonts')/'Nunito-Black.ttf'))
    def text(body,at,size,color,align='CENTER'):
        curve=k.bpy.data.curves.new('Rounded bold lettering '+body,'FONT')
        curve.body=body;curve.font=font;curve.align_x=align;curve.size=size
        curve.extrude=.004;curve.resolution_u=2;curve.offset=0
        o=k.bpy.data.objects.new('Lettering '+body,curve);k.bpy.context.scene.collection.objects.link(o)
        o.location=k.v((at[0],at[1],at[2]+.005));o.rotation_euler.x=math.pi/2
        k.bpy.ops.object.select_all(action='DESELECT');o.select_set(True);k.bpy.context.view_layer.objects.active=o
        k.bpy.ops.object.convert(target='MESH')
        obj=k.finish(k.bpy.context.object,'Lettering '+body,color)
        obj['atlas_constant_colour']=True
        return obj
    k.text_label=text

def fit_camera(d,reference_size,corners,footprint=(6.18,5.68),plinth_y=-.15):
    """Fit three observed edge intersections; infer the obscured fourth.
    Output is square, with the same undistorted letterbox as package_series.
    Least-squares vertical fit records residual instead of deforming the model.
    """
    w,h=reference_size;factor=1400/max(w,h);ox=(1400-w*factor)/2;oy=(1400-h*factor)/2
    pts=[(x*factor+ox,y*factor+oy) for x,y in corners];left,front,right=pts
    dx=(front[0]-left[0],front[1]-left[1]);dz=(front[0]-right[0],front[1]-right[1])
    import numpy as np
    width,depth=footprint
    world=np.array([(-width/2,depth/2),(width/2,depth/2),(width/2,-depth/2)])
    obs=np.array(pts);centered=obs-obs.mean(axis=0)
    yaw,pitch=math.radians(42),math.radians(32)
    best=None
    for radius,step in ((24,1),(1.5,.10),(.15,.01)):
        yaws=np.radians(np.arange(math.degrees(yaw)-radius,math.degrees(yaw)+radius+step/2,step))
        pitches=np.radians(np.arange(math.degrees(pitch)-radius,math.degrees(pitch)+radius+step/2,step))
        yy,pp=np.meshgrid(yaws,pitches);yy=yy.ravel();pp=pp.ravel()
        px=np.cos(yy)[:,None]*world[:,0]-np.sin(yy)[:,None]*world[:,1]
        py=np.sin(pp)[:,None]*(np.sin(yy)[:,None]*world[:,0]+np.cos(yy)[:,None]*world[:,1])
        unit=np.stack((px,py),axis=2);cen=unit-unit.mean(axis=1)[:,None,:]
        ss=(cen*centered).sum(axis=(1,2))/(cen*cen).sum(axis=(1,2))
        err=((cen*ss[:,None,None]-centered)**2).sum(axis=(1,2));i=int(err.argmin())
        yaw,pitch,scale=float(yy[i]),float(pp[i]),float(ss[i]);rel=unit[i]*scale
        origin=obs.mean(axis=0)-rel.mean(axis=0)
    rel=rel.tolist();origin=origin.tolist()
    offset=(700-origin[0])/scale;focus=plinth_y+(origin[1]-700)/(scale*math.cos(pitch))
    target=[math.cos(yaw)*offset,focus,-math.sin(yaw)*offset]
    d['camera']={'position':[target[0]+15*math.sin(yaw),focus+15*math.tan(pitch),target[2]+15*math.cos(yaw)],'target':target,'size':1400/scale}
    fit={'method':'orthographic fit to plinth edge intersections; no model scaling or image warp','reference_size':list(reference_size),'reference_corners_left_front_right':corners,'inferred_back':[corners[0][0]+corners[2][0]-corners[1][0],corners[0][1]+corners[2][1]-corners[1][1]],'footprint_m':list(footprint),'plinth_y':plinth_y,'render_size':[1400,1400],'fitted_corners':[[origin[j]+p[j] for j in (0,1)] for p in rel],'observed_letterboxed_corners':pts,'residual_px':[math.dist(pts[i],[origin[j]+rel[i][j] for j in (0,1)]) for i in range(3)],'pitch_degrees':math.degrees(pitch),'yaw_degrees':math.degrees(yaw),'camera':d['camera'],'limitation':'Rounded plinth endpoints are estimated edge intersections; concept is not a calibrated physical camera.'}
    (k.SOURCE/'camera-r2.json').write_text(json.dumps(fit,indent=2)+'\n')
    d['review_camera_fit']=fit
    if hasattr(k,'bpy') and k.bpy.context.scene.camera:
        cam=k.bpy.context.scene.camera;cam.location=k.v(d['camera']['position'])
        cam.rotation_euler=(k.v(d['camera']['target'])-cam.location).to_track_quat('-Z','Y').to_euler()
        cam.data.ortho_scale=d['camera']['size']
