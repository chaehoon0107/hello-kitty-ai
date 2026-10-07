from pathlib import Path
import numpy as np
from glb import read,accessor

root=Path(__file__).resolve().parents[1]
doc,blob=read(root/'assets/pet_blender_rigged.glb')
assert len(doc['skins'][0]['joints'])==16
assert {a['name'] for a in doc['animations']}=={'Idle','Walk','Think','Notice'}
walk=next(a for a in doc['animations'] if a['name']=='Walk')
for bone in ['Thigh.L','Thigh.R','Shin.L','UpperArm.L']:
    channel=next(c for c in walk['channels'] if doc['nodes'][c['target']['node']]['name']==bone and c['target']['path']=='rotation')
    values=accessor(doc,blob,walk['samplers'][channel['sampler']]['output'])
    values=values/np.linalg.norm(values,axis=1,keepdims=True)
    variation=float(np.max(2*np.arccos(np.clip(np.abs(values @ values[0]),0,1))))
    assert variation>.04,(bone,'Animation is static',variation)
    print(bone,'rotation changes in radians',round(variation,3))
shared_weights={}
maximum_seam_weight_error=0.0
for mesh in doc['meshes']:
    for primitive in mesh['primitives']:
        weights=accessor(doc,blob,primitive['attributes']['WEIGHTS_0'])
        assert np.allclose(weights.sum(axis=1),1,atol=.001)
        positions=accessor(doc,blob,primitive['attributes']['POSITION'])
        joints=accessor(doc,blob,primitive['attributes']['JOINTS_0']).astype(int)
        for pos,joint,weight in zip(positions,joints,weights):
            dense=np.zeros(16);np.add.at(dense,joint,weight)
            key=tuple(np.round(pos,5))
            if key in shared_weights:
                maximum_seam_weight_error=max(maximum_seam_weight_error,float(np.max(np.abs(shared_weights[key]-dense))))
            else:shared_weights[key]=dense
assert maximum_seam_weight_error<1e-5,('Exported material seams can separate',maximum_seam_weight_error)
for clip in doc['animations']:
    for channel in clip['channels']:
        sampler=clip['samplers'][channel['sampler']]
        values=accessor(doc,blob,sampler['output'])
        if channel['target']['path']=='rotation':
            assert abs(float(values[0] @ values[-1]))>.99999,(clip['name'],'Rotation loop must be seamless')
        else:assert np.allclose(values[0],values[-1],atol=1e-5),(clip['name'],'Position loop must be seamless')
duration=max(float(accessor(doc,blob,s['input'])[-1,0]) for s in walk['samplers'])
print('Material seam weight error',maximum_seam_weight_error,'walk key duration',duration)
print('BLENDER_EXPORTED_RIG_VALID')
