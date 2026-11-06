import sys,time; sys.path.insert(0,'.')
from art_bg import *
for th in ("jungle","tundra"):
    t=time.time()
    b=background(th,0); f=foreground(th,0)
    b.paste(f,0,0)
    # lay tiles for preview
    g=ground_tile(th,0); 
    for gy in range(GH):
        for gx in range(GW):
            x,y=proj(gx+0.5,gy+0.5)
            b.paste(ground_tile(th,(gx+gy*3)%4),int(x-TW/2),int(y-TH/2))
    b.to_image().save(f"/tmp/bg_{th}.png"); print(th,time.time()-t)
