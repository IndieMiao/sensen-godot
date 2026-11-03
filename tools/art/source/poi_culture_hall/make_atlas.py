"""N3 hall skin plus exact, used-only botanical tiles in one RGBA atlas."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/"assets/rooms/poi_culture_hall"
HALL=ROOT/"assets/rooms/_shared/shell_hall";PLANTS=ROOT/"assets/rooms/_shared/plants"
sys.path.insert(0,str(ROOT/"tools/art"))
from verify_chef_sign import load_glb,accessor
COLORS={"parquet":"D88E56","floor_solid":"D88E56","plaster":"F5DAC0","plaster_solid":"F5DAC0",
    "panel":"E1BE9A","wainscot_solid":"E1BE9A","cornice":"E9C5A0","cornice_solid":"E9C5A0",
    "skirting":"D3AA85","window":"F0D3AE","window_solid":"F0D3AE","wood_mid":"AE6F45",
    "wood_dark":"694528","oak":"9F683F","oak_light":"BB8758","oak_edge":"9B633C",
    "brass":"B98D42","porcelain":"FFF0D4","linen":"EFDFBD","cloth_green":"6E7C46",
    "sage_dark":"34431C","iron":"5C5143"}
def main():
    palette=json.loads((HALL/"hall_palette.json").read_text())
    pixels=np.asarray(Image.open(HALL/"hall_albedo_ao.png").convert("RGBA")).astype(float).copy()
    for key,slot in palette["slots"].items():
        old=np.array(list(bytes.fromhex(slot["hex_srgb"])),float);color=COLORS.get(key,slot["hex_srgb"])
        rgb=np.array(list(bytes.fromhex(color)),float);x,y,w,h=slot["rect_px_top_left"]
        shade=np.mean(pixels[y:y+h,x:x+w,:3]/np.maximum(old,1),axis=2)
        pixels[y:y+h,x:x+w,:3]=np.clip(rgb*shade[...,None],0,255);slot["hex_srgb"]=color
    atlas=Image.fromarray(pixels.astype(np.uint8))
    x,y,w,h=palette["slots"]["parquet"]["safe_rect_px_top_left"]
    yy,xx=np.mgrid[0:h,0:w];u=xx/w*12;v=yy/h*13
    col,row=np.floor(u),np.floor(v);edge=np.minimum.reduce([u-col,1-u+col,v-row,1-v+row])
    shade=1+.025*np.sin(col*7.13+row*4.97)+.008*np.sin(xx*.032+yy*.027)
    shade*=np.where(edge<.014,.82,np.where(edge<.031,1.04,1))
    rgb=np.array(list(bytes.fromhex(COLORS["parquet"])),float)
    tile=np.empty((h,w,4),np.uint8);tile[:,:,:3]=np.clip(rgb*shade[...,None],0,255);tile[:,:,3]=255
    atlas.paste(Image.fromarray(tile),(x,y))
    doc,blob=load_glb(PLANTS/"monstera.glb")
    uv=np.concatenate([np.array(accessor(doc,blob,p["attributes"]["TEXCOORD_0"])) for m in doc["meshes"] for p in m["primitives"]])
    tiles=np.unique(np.floor(uv*16).astype(int),axis=0);assert len(tiles)<=12
    plant=Image.open(PLANTS/"room_albedo_ao.png").convert("RGBA");mapping=[]
    for index,(col,row) in enumerate(tiles):
        slot=["leaf","leaf_light","leaf_dark"][index//4]
        sx,sy,_,_=palette["slots"][slot]["rect_px_top_left"]
        dx,dy=sx+(index%2)*128,sy+((index%4)//2)*128
        source=[int(col)*128,int(row)*128,128,128];dest=[dx,dy,128,128]
        atlas.paste(plant.crop((source[0],source[1],source[0]+128,source[1]+128)),(dx,dy))
        mapping.append(dict(source_rect_px=source,target_rect_px=dest,source_tile=[int(col),int(row)]))
    for key in ["leaf","leaf_light","leaf_dark"]:
        palette["slots"][key]["kind"]="botanical_tile_bank"
        palette["slots"][key]["recolor"]="Preserve the copied RGBA tiles and alpha masks; this is not a solid swatch."
    palette["reserved_for_furniture"]=[key for key in palette["reserved_for_furniture"] if key not in ["leaf","leaf_light","leaf_dark"]]
    atlas.save(OUT/"room_albedo_ao.png")
    palette.update(atlas="room_albedo_ao.png",stage="reuse_preassembly",author="ZHAOYUN",task="SGODOT-323",
        reference_palette=dict(wall="F5DAC0",floor="D88E56",furniture="EFDFBD",accent="465823"),
        botanical_tiles=mapping,botanical_source_sha256=hashlib.sha256((PLANTS/"room_albedo_ao.png").read_bytes()).hexdigest(),
        notes=["Shared hall geometry/UV unchanged. Terracotta tile bitmap replaces parquet region only; floor UV remains rotated 90 degrees.",
            "Bench albedo 6E7C46 compensates the unchanged shaded seating area toward the reference appearance 465823; other lighting is not brightened globally.",
            "Monstera's ten used 128px tiles are copied byte-for-byte with their original 12px guards and alpha silhouette.",
            "Botanical tiles occupy leaf/leaf_light/leaf_dark reserved regions; opaque furniture never samples these slots.",
            "Huangzhong's cases, art, plinth, exhibits, mosaic and sign remain unchanged gray placeholders."])
    (OUT/"atlas_skin.json").write_text(json.dumps(palette,indent=2)+"\n")
    print("CULTURE_ATLAS",len(mapping),"botanical tiles; one 2048 RGBA image")
if __name__=="__main__":main()
