import bpy,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'tools/parts_base.glb'))
for obj in list(bpy.context.scene.objects):
    if obj.type!='MESH':continue
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    print('PART',obj.name,len(obj.data.vertices),len(obj.data.polygons))
    for p in obj.data.polygons:p.use_smooth=True
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE_NEXT'
scene.render.resolution_x=768;scene.render.resolution_y=768
scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
for loc,power,size in [((-2,-3,3),180,3),((2,-2,1),70,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.size=size
    o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-3,0));o=bpy.context.object;o.data.type='ORTHO';o.data.ortho_scale=1.16
o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler();scene.camera=o
scene.render.filepath=str(ROOT/'previews/new_parts_front.png')
bpy.ops.render.render(write_still=True)
