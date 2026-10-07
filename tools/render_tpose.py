"""Render the supplied mesh in its original T-pose using Blender."""
import bpy
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root / 'tools/pet_base.glb'))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
assert meshes, 'The source model did not import'
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.view_settings.view_transform = 'AgX'
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (1, 1, 1, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35

def area_light(name, position, power, size):
    bpy.ops.object.light_add(type='AREA', location=position)
    light = bpy.context.object
    light.name = name
    light.data.energy = power
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()

area_light('Soft key', (-2.0, -3.0, 3.0), 180, 3.0)
area_light('Soft fill', (2.5, -2.5, 1.0), 95, 3.0)
area_light('Rim light', (0.0, 2.0, 2.5), 120, 2.5)
bpy.ops.object.camera_add(location=(0, -3, 0))
camera = bpy.context.object
camera.name = 'T-pose front camera'
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 1.15
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
scene.render.filepath = str(root / 'previews/blender_tpose_full.png')
bpy.ops.wm.save_as_mainfile(filepath=str(root / 'tools/pet_tpose.blend'))
bpy.ops.render.render(write_still=True)
print('BLENDER_TPOSE_RENDER_COMPLETE', scene.render.filepath)
