from pathlib import Path
import numpy as np
from glb import read,accessor
root=Path(__file__).resolve().parents[1]
doc,blob=read(root/'assets/pet_smooth_parts.glb')
positions=[];triangles=[];owners=[];offset=0
for node in doc['nodes']:
    if 'mesh' not in node:continue
    p=doc['meshes'][node['mesh']]['primitives'][0]
    vertices=accessor(doc,blob,p['attributes']['POSITION'])
    positions.append(vertices);owners.extend([node['name']]*len(vertices))
    triangles.append(accessor(doc,blob,p['indices']).ravel().reshape(-1,3)+offset)
    offset+=len(vertices)
points=np.concatenate(positions);faces=np.concatenate(triangles)
unique,inverse=np.unique(np.round(points,5),axis=0,return_inverse=True)
edges=np.sort(np.concatenate([inverse[faces][:,[0,1]],inverse[faces][:,[1,2]],inverse[faces][:,[2,0]]]),axis=1)
ue,counts=np.unique(edges,axis=0,return_counts=True)
print('ALL_BOUNDARIES',sum(counts==1),'NONMANIFOLD',sum(counts>2))
shared=[]
for vi,p in enumerate(unique):
    indices=np.where(inverse==vi)[0]
    parts=set(owners[i] for i in indices)
    if len(parts)>1:shared.append((p,parts))
print('SHARED_PART_VERTICES',len(shared))
for arm in ['tripo_part_3','tripo_part_7']:
    groups=[(p,parts) for p,parts in shared if arm in parts]
    print(arm,'shared',len(groups),'position span',np.array([x[0] for x in groups]).min(0),np.array([x[0] for x in groups]).max(0))
