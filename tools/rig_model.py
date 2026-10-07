"""Create an editable glTF skeleton, skin weights and baked walk without Blender."""
from pathlib import Path
import math,json
import numpy as np
from glb import read,accessor,append,write

ROOT=Path(__file__).resolve().parents[1]
doc,blob=read(ROOT/'tools/pet_base.glb')
primitive=doc['meshes'][0]['primitives'][0]
points=accessor(doc,blob,primitive['attributes']['POSITION'])
# Global joint positions. Joint axes stay aligned with the model axes.
bones=[
 ('Root',None,(0,0,0)),
 ('Hips','Root',(0,-.335,0)),
 ('Spine','Hips',(0,-.235,0)),
 ('Head','Spine',(0,-.09,0)),
 ('UpperArm.L','Spine',(.16,-.14,0)),
 ('Forearm.L','UpperArm.L',(.285,-.14,0)),
 ('Hand.L','Forearm.L',(.375,-.14,0)),
 ('UpperArm.R','Spine',(-.16,-.14,0)),
 ('Forearm.R','UpperArm.R',(-.285,-.14,0)),
 ('Hand.R','Forearm.R',(-.375,-.14,0)),
 ('Thigh.L','Hips',(.09,-.355,0)),
 ('Shin.L','Thigh.L',(.09,-.415,0)),
 ('Foot.L','Shin.L',(.09,-.465,.015)),
 ('Thigh.R','Hips',(-.09,-.355,0)),
 ('Shin.R','Thigh.R',(-.09,-.415,0)),
 ('Foot.R','Shin.R',(-.09,-.465,.015)),
]
lookup={name:i for i,(name,_,_) in enumerate(bones)}
doc['nodes']=[{'name':'PetMesh','mesh':0,'skin':0}]
for name,parent,pos in bones:
    parent_pos=np.array(bones[lookup[parent]][2]) if parent else np.zeros(3)
    doc['nodes'].append({'name':name,'translation':(np.array(pos)-parent_pos).tolist()})
    if parent:doc['nodes'][lookup[parent]+1].setdefault('children',[]).append(lookup[name]+1)
doc['scenes']=[{'name':'RiggedPet','nodes':[0,1]}];doc['scene']=0
inv=[]
for _,_,pos in bones:
    matrix=np.eye(4,dtype='<f4');matrix[:3,3]=-np.array(pos);inv.append(matrix.T.reshape(-1))
bind=append(doc,blob,np.array(inv,dtype='<f4'),'MAT4')
doc['skins']=[{'name':'PetSkin','inverseBindMatrices':bind,'skeleton':1,'joints':list(range(1,len(bones)+1))}]

def smooth(a,b,x):
    t=float(np.clip((x-a)/(b-a),0,1));return t*t*(3-2*t)

weights=np.zeros((len(points),len(bones)),dtype='<f4')
for i,(x,y,z) in enumerate(points):
    side='L' if x>=0 else 'R';ax=abs(x)
    if -.20<y<-.085 and ax>.19 and z>-.09:
        # Sleeves and hands; blend gently at the shoulder attachment.
        arm=smooth(.19,.235,ax)
        elbow=smooth(.255,.32,ax);hand=smooth(.35,.395,ax)
        w={'Spine':1-arm,'UpperArm.'+side:arm*(1-elbow),
           'Forearm.'+side:arm*elbow*(1-hand),'Hand.'+side:arm*elbow*hand}
    elif y>=-.075:
        w={'Head':1}
    elif y>-.105:
        h=smooth(-.105,-.075,y);w={'Head':h,'Spine':1-h}
    elif y<-.335:
        leg=1-smooth(-.365,-.335,y)
        knee=1-smooth(-.437,-.393,y);foot=1-smooth(-.468,-.442,y)
        center=smooth(.0,.04,ax);leg*=center
        w={'Hips':1-leg,'Thigh.'+side:leg*(1-knee),
           'Shin.'+side:leg*knee*(1-foot),'Foot.'+side:leg*knee*foot}
    else:
        h=smooth(-.31,-.20,y);w={'Hips':1-h,'Spine':h}
    for name,value in w.items():weights[i,lookup[name]]=value
joints=np.argsort(-weights,axis=1)[:,:4].astype('<u2')
skin_weights=np.take_along_axis(weights,joints,axis=1)
skin_weights/=np.maximum(skin_weights.sum(1,keepdims=True),1e-9)
primitive['attributes']['JOINTS_0']=append(doc,blob,joints,'VEC4',5123,34962)
primitive['attributes']['WEIGHTS_0']=append(doc,blob,skin_weights.astype('<f4'),'VEC4',5126,34962)

def quat(axis,angle):
    xyz=np.array(axis)*math.sin(angle/2);return np.r_[xyz,math.cos(angle/2)]
def mul(a,b):
    return np.r_[a[3]*b[:3]+b[3]*a[:3]+np.cross(a[:3],b[:3]),a[3]*b[3]-np.dot(a[:3],b[:3])]

doc['animations']=[]
duration=.8
times=np.linspace(0,duration,33,dtype='<f4')
for anim_name in ['Idle','Walk']:
    anim={'name':anim_name,'samplers':[],'channels':[]}
    time_accessor=append(doc,blob,times.reshape(-1,1),'SCALAR')
    doc['accessors'][time_accessor].update(min=[0],max=[duration])
    def track(name,path,data,kind):
        output=append(doc,blob,np.array(data,dtype='<f4'),kind)
        index=len(anim['samplers']);anim['samplers'].append({'input':time_accessor,'output':output,'interpolation':'LINEAR'})
        anim['channels'].append({'sampler':index,'target':{'node':lookup[name]+1,'path':path}})
    rotations={name:[] for name in lookup};root=[]
    for t in times:
        phase=float(t/duration*2*math.pi);walk=anim_name=='Walk'
        sway=math.sin(phase) if walk else 0
        for name in lookup:
            q=np.array([0,0,0,1.])
            if name.startswith('UpperArm'):
                sign=1 if name.endswith('L') else -1
                # Lower the source T-pose, then swing opposite the corresponding leg.
                q=mul(quat((1,0,0),-sign*sway*.22),quat((0,0,1),-sign*math.radians(76)))
            elif name.startswith('Thigh'):
                sign=1 if name.endswith('L') else -1;q=quat((1,0,0),sign*sway*.45)
            elif name.startswith('Shin'):
                sign=1 if name.endswith('L') else -1;q=quat((1,0,0),-max(0,-sign*sway)*.48)
            elif name.startswith('Foot'):
                sign=1 if name.endswith('L') else -1;q=quat((1,0,0),-sign*sway*.10)
            elif name=='Head' and walk:q=quat((0,0,1),sway*.018)
            elif name=='Spine' and walk:q=quat((0,0,1),-sway*.014)
            rotations[name].append(q)
        root.append([0,.006*(1-math.cos(phase*2)) if walk else 0,0])
    for name,data in rotations.items():track(name,'rotation',data,'VEC4')
    track('Root','translation',root,'VEC3')
    doc['animations'].append(anim)
doc['asset']['generator']='Desktop Pet rig builder (no Blender)'
write(doc,blob,ROOT/'assets/pet_rigged.glb')
(ROOT/'assets/rig_info.json').write_text(json.dumps({'bones':[b[0] for b in bones],'vertices':len(points),'animations':['Idle','Walk'],'walk_duration':duration},indent=2))
assert np.allclose(skin_weights.sum(1),1)
assert np.isfinite(skin_weights).all()
print('Rig complete:',len(bones),'bones,',len(points),'weighted vertices, Idle + Walk')
