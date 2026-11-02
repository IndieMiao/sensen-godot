"""Pale-lavender quartz in sRGB, converted once to linear vertex colour."""
import math

DARK=(169/255,165/255,181/255)
MID=(180/255,179/255,186/255)
LIGHT=(200/255,198/255,206/255)
KEY=(-.4,.65,1.)

def linear(value):
    return value/12.92 if value<=.04045 else ((value+.055)/1.055)**2.4

def facet_colours(normals):
    direction=[v/math.sqrt(sum(x*x for x in KEY)) for v in KEY]
    scores=[]
    for normal in normals:
        length=math.sqrt(sum(v*v for v in normal))
        scores.append(sum(v/length*d for v,d in zip(normal,direction)))
    lo=min(scores);span=max(scores)-lo
    result=[]
    for score in scores:
        weight=(score-lo)/span if span>1e-8 else .6
        a,b,t=(DARK,MID,weight/.35) if weight<.35 else (MID,LIGHT,(weight-.35)/.65)
        srgb=[x+(y-x)*t for x,y in zip(a,b)]
        result.append([linear(value) for value in srgb])
    return result
