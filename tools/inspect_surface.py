from pathlib import Path
import io
import numpy as np
from PIL import Image
from glb import read,accessor
root=Path(__file__).resolve().parents[1]
doc,blob=read(root/'tools/parts_base.glb')
for node in doc['nodes']:
    if 'mesh' not in node:continue
    mesh=doc['meshes'][node['mesh']]
    for primitive in mesh['primitives']:
        p=accessor(doc,blob,primitive['attributes']['POSITION'])
        idx=accessor(doc,blob,primitive['indices']).ravel().reshape(-1,3)
        unique,inverse=np.unique(np.round(p,5),axis=0,return_inverse=True)
        triangles=inverse[idx]
        edges=np.sort(np.concatenate([triangles[:,[0,1]],triangles[:,[1,2]],triangles[:,[2,0]]]),axis=1)
        _,counts=np.unique(edges,axis=0,return_counts=True)
        print(node['name'],'verts',len(p),'unique',len(unique),'boundary',sum(counts==1),'nonmanifold',sum(counts>2))
        if node['name'] in ['tripo_part_0','tripo_part_3']:
            material=doc['materials'][primitive['material']]
            tex=material['pbrMetallicRoughness']['baseColorTexture']['index']
            image=doc['images'][doc['textures'][tex]['source']]
            v=doc['bufferViews'][image['bufferView']];start=v.get('byteOffset',0)
            im=Image.open(io.BytesIO(blob[start:start+v['byteLength']]))
            im.save(root/'previews'/f"{node['name']}_texture.png")
            print('texture',im.size)
