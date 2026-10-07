import json,struct
from pathlib import Path
import numpy as np

def read(path):
    data=Path(path).read_bytes();size=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+size]),bytearray(data[28+size:])

def accessor(doc,blob,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    dtype={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    d=np.dtype(dtype);offset=v.get('byteOffset',0)+a.get('byteOffset',0)
    result=np.ndarray((a['count'],width),dtype=d,buffer=blob,offset=offset,strides=(v.get('byteStride',d.itemsize*width),d.itemsize)).copy()
    if a.get('normalized'):
        result=result.astype('float32')/np.iinfo(d).max
        result=np.maximum(-1,result)
    return result

def append(doc,blob,data,kind,component=5126,target=None):
    blob.extend(b'\0'*((-len(blob))%4));off=len(blob);data=np.ascontiguousarray(data)
    blob.extend(data.tobytes());v={'buffer':0,'byteOffset':off,'byteLength':data.nbytes}
    if target:v['target']=target
    view=len(doc['bufferViews']);doc['bufferViews'].append(v)
    a={'bufferView':view,'componentType':component,'count':len(data),'type':kind}
    if kind=='VEC3':a.update(min=data.min(axis=0).tolist(),max=data.max(axis=0).tolist())
    index=len(doc['accessors']);doc['accessors'].append(a);return index

def write(doc,blob,path):
    doc['buffers']=[{'byteLength':len(blob)}];blob.extend(b'\0'*((-len(blob))%4))
    j=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();j+=b' '*((-len(j))%4)
    Path(path).write_bytes(struct.pack('<IIIII',0x46546c67,2,28+len(j)+len(blob),len(j),0x4e4f534a)+j+struct.pack('<II',len(blob),0x004e4942)+blob)

if __name__=='__main__':
    root=Path(__file__).resolve().parents[1];doc,blob=read(root/'tools/source_decoded.glb')
    for primitive in doc['meshes'][0]['primitives']:
        p=accessor(doc,blob,primitive['attributes']['POSITION']);p=p[:,[2,1,0]];p[:,0]*=-1
        primitive['attributes']['POSITION']=append(doc,blob,p.astype('<f4'),'VEC3',target=34962)
        n=accessor(doc,blob,primitive['attributes']['NORMAL']);n/=np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-8)
        n=n[:,[2,1,0]];n[:,0]*=-1
        primitive['attributes']['NORMAL']=append(doc,blob,n.astype('<f4'),'VEC3',target=34962)
    doc.pop('extensionsRequired',None);doc.pop('extensionsUsed',None)
    write(doc,blob,root/'tools/pet_base.glb')
