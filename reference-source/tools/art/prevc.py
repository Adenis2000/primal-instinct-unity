import sys; sys.path.insert(0,'.')
from art_creatures import *
from preview import sheet
d=build_enemies()
names=[k for k in d if not k.endswith('_b')]
items=[d[k] for k in names]
im=sheet(items,4,120,100,(70,100,70)); im=im.resize((im.width*2,im.height*2),Image.NEAREST); im.save('/tmp/prev_enemies.png')
items=[d[k+'_b'] for k in names]
im=sheet(items,4,120,100,(70,100,70)); im.save('/tmp/prev_enemies_b.png')
