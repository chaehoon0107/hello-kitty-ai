"""Pad texture islands to prevent dark UV seams in the desktop-size model."""
from pathlib import Path
from io import BytesIO
import json
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from glb import read,write

root=Path(__file__).resolve().parents[1]
doc,blob=read(root/'tools/parts_base.glb')
fixed=[]
for material in doc['materials']:
    texture_index=material['pbrMetallicRoughness']['baseColorTexture']['index']
    image_index=doc['textures'][texture_index]['source']
    if image_index in fixed:continue
    entry=doc['images'][image_index]
    view=doc['bufferViews'][entry['bufferView']]
    off=view.get('byteOffset',0)
    image=Image.open(BytesIO(blob[off:off+view['byteLength']])).convert('RGB')
    pixels=np.array(image)
    # These supplied atlases use black for the unused background. Preserve the
    # coloured eyes, whiskers and all other painted pixels; extend the islands
    # into the blank area so every mip level has matching border texels.
    empty=pixels.max(axis=2)<32
    distance,nearest=distance_transform_edt(empty,return_indices=True)
    padding=empty & (distance<=48)
    pixels[padding]=pixels[nearest[0][padding],nearest[1][padding]]
    encoded=BytesIO();Image.fromarray(pixels).save(encoded,format='PNG')
    data=encoded.getvalue();blob.extend(b'\0'*((-len(blob))%4));offset=len(blob);blob.extend(data)
    entry['bufferView']=len(doc['bufferViews']);entry['mimeType']='image/png'
    entry['name']=entry.get('name',f'Color {image_index}')+' padded'
    doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
    fixed.append(image_index)
write(doc,blob,root/'assets/pet_smooth_parts.glb')
(root/'previews/surface_repair.json').write_text(json.dumps({
    'source':'tools/parts_base.glb','model':'assets/pet_smooth_parts.glb',
    'meshes':len(doc['meshes']),'padded_color_textures':len(fixed),
    'padding_pixels':48,'geometry_changed':False,'pose_changed':False,
    'lighting':'unshaded'
},indent=2))
print('PADDED_MODEL_READY',len(fixed),'textures; original geometry preserved')
