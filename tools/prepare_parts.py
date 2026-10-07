from pathlib import Path
import numpy as np
from glb import read,accessor,append,write
root=Path(__file__).resolve().parents[1]
doc,blob=read(root/'tools/parts_decoded.glb')
for mi,mesh in enumerate(doc['meshes']):
    for p in mesh['primitives']:
        pos=accessor(doc,blob,p['attributes']['POSITION']).astype('float32')
        print(doc['nodes'][mi]['name'],len(pos),'min',pos.min(0).round(4),'max',pos.max(0).round(4),'mean',pos.mean(0).round(4))
        pos=pos[:,[2,1,0]];pos[:,0]*=-1
        p['attributes']['POSITION']=append(doc,blob,pos,'VEC3',target=34962)
        n=accessor(doc,blob,p['attributes']['NORMAL']).astype('float32')
        n/=np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-8)
        n=n[:,[2,1,0]];n[:,0]*=-1
        p['attributes']['NORMAL']=append(doc,blob,n,'VEC3',target=34962)
doc.pop('extensionsRequired',None);doc.pop('extensionsUsed',None)
write(doc,blob,root/'tools/parts_base.glb')
