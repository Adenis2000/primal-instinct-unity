import sys; sys.path.insert(0,'.')
from art_env import *
def sheet(items, cols, cw, ch, bg=(40,50,40)):
    rows=(len(items)+cols-1)//cols
    s=Canvas(cols*cw, rows*ch); s.px[:,:,:3]=bg; s.px[:,:,3]=255
    for i,it in enumerate(items):
        s.paste(it,(i%cols)*cw+(cw-it.w)//2,(i//cols)*ch+(ch-it.h)//2)
    im=s.to_image(); im=im.resize((im.width*2,im.height*2),Image.NEAREST); return im
if __name__=="__main__":
    for th in ("jungle","tundra"):
        items=[ground_tile(th,v) for v in range(5)]+[ground_tile(th,0,"tall")]+[water_tile(th,f) for f in range(3)]
        items+=[boulders(th,0),boulders(th,1),log_prop(th,0),log_prop(th,1),ruin_block(th,0),ruin_block(th,1),pine_prop(th,0),fern_bush(th,0) if th=="jungle" else ice_crystals(th,0),tall_grass(th,0),tall_grass(th,1),tall_grass(th,0,True)]
        sheet(items,6,84,100).save(f"/tmp/prev_{th}.png")
