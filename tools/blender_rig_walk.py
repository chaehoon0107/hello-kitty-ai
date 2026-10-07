"""Build a real Blender armature, planted-foot walk, and editable cartoon preview."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.context.scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'tools/pet_base.glb'))
mesh = next(o for o in scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh.name = 'PetMesh'
# Smooth across UV seams without welding away the supplied texture coordinates.
normal_sums={}
for polygon in mesh.data.polygons:
    polygon.use_smooth=True
    for vertex_index in polygon.vertices:
        key=tuple(round(v,5) for v in mesh.data.vertices[vertex_index].co)
        normal_sums.setdefault(key,Vector((0,0,0)))
        normal_sums[key]+=polygon.normal*polygon.area
smooth_normals=[tuple(normal_sums[tuple(round(v,5) for v in vertex.co)].normalized()) for vertex in mesh.data.vertices]
mesh.data.normals_split_custom_set_from_vertices(smooth_normals)

# Coordinates are specified in the original upright glTF basis.
bones = [
    ('Root', None, (0,0,0), (0,.08,0)),
    ('Hips','Root',(0,-.335,0),(0,-.27,0)),
    ('Spine','Hips',(0,-.235,0),(0,-.10,0)),
    ('Head','Spine',(0,-.09,0),(0,.30,0)),
    ('UpperArm.L','Spine',(.16,-.14,0),(.285,-.14,0)),
    ('Forearm.L','UpperArm.L',(.285,-.14,0),(.375,-.14,0)),
    ('Hand.L','Forearm.L',(.375,-.14,0),(.41,-.14,0)),
    ('UpperArm.R','Spine',(-.16,-.14,0),(-.285,-.14,0)),
    ('Forearm.R','UpperArm.R',(-.285,-.14,0),(-.375,-.14,0)),
    ('Hand.R','Forearm.R',(-.375,-.14,0),(-.41,-.14,0)),
    ('Thigh.L','Hips',(.09,-.355,0),(.09,-.415,0)),
    ('Shin.L','Thigh.L',(.09,-.415,0),(.09,-.465,0)),
    ('Foot.L','Shin.L',(.09,-.465,0),(.09,-.465,.085)),
    ('Thigh.R','Hips',(-.09,-.355,0),(-.09,-.415,0)),
    ('Shin.R','Thigh.R',(-.09,-.415,0),(-.09,-.465,0)),
    ('Foot.R','Shin.R',(-.09,-.465,0),(-.09,-.465,.085)),
]
def to_blender(point): return Vector((point[0], -point[2], point[1]))

arm_data = bpy.data.armatures.new('PetSkeleton')
rig = bpy.data.objects.new('PetRig', arm_data)
scene.collection.objects.link(rig)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
for name, parent, head, tail in bones:
    bone = arm_data.edit_bones.new(name)
    bone.head = to_blender(head)
    bone.tail = to_blender(tail)
    if parent: bone.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
rig.show_in_front = True
arm_data.display_type = 'STICK'
mesh.parent = rig
modifier = mesh.modifiers.new('Pet skin', 'ARMATURE')
modifier.object = rig
groups = {name:mesh.vertex_groups.new(name=name) for name,_,_,_ in bones}

def smooth(a,b,x):
    t = max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)

for vertex in mesh.data.vertices:
    x,y,z = vertex.co.x, vertex.co.z, -vertex.co.y
    side = 'L' if x >= 0 else 'R'
    ax = abs(x)
    if -.20 < y < -.085 and ax > .19 and z > -.09:
        arm=smooth(.19,.235,ax); elbow=smooth(.255,.32,ax); hand=smooth(.35,.395,ax)
        weights={'Spine':1-arm,'UpperArm.'+side:arm*(1-elbow),
                 'Forearm.'+side:arm*elbow*(1-hand),'Hand.'+side:arm*elbow*hand}
    elif y >= -.075:
        weights={'Head':1}
    elif y > -.105:
        head=smooth(-.105,-.075,y); weights={'Head':head,'Spine':1-head}
    elif y < -.335:
        leg=(1-smooth(-.365,-.335,y))*smooth(0,.035,ax)
        knee=1-smooth(-.43,-.398,y)
        # Assign the complete boot to Foot so its sole stays rigid and flat.
        foot=1-smooth(-.446,-.428,y)
        weights={'Hips':1-leg,'Thigh.'+side:leg*(1-knee),
                 'Shin.'+side:leg*knee*(1-foot),'Foot.'+side:leg*knee*foot}
    else:
        spine=smooth(-.31,-.20,y); weights={'Hips':1-spine,'Spine':spine}
    total=sum(weights.values())
    for name,weight in weights.items():
        if weight > .00001:groups[name].add([vertex.index],weight/total,'REPLACE')

for bone in rig.pose.bones: bone.rotation_mode='QUATERNION'
rest_rotations={bone.name:bone.matrix_local.to_quaternion() for bone in arm_data.bones}

def rotate(name, rotation):
    rest=rest_rotations[name]
    rig.pose.bones[name].rotation_quaternion=rest.inverted() @ rotation @ rest

def hinge(name,axis,angle): rotate(name,Quaternion(to_blender(axis),angle))

def foot_path(progress):
    stride=.0365
    if progress < .5:
        return stride*(1-4*progress),0
    u=(progress-.5)*2
    # Smooth return through the air, with the same backward velocity at landing.
    h00=2*u**3-3*u*u+1;h10=u**3-2*u*u+u
    h01=-2*u**3+3*u*u;h11=u**3-u*u
    forward=h00*(-stride)+h10*(-2*stride)+h01*stride+h11*(-2*stride)
    return forward,.015*math.sin(math.pi*u)**2

def pose(progress,walking):
    phase=2*math.pi*progress
    for bone in rig.pose.bones:
        bone.location=(0,0,0)
        bone.rotation_quaternion=(1,0,0,0)
    bob=-.009+.0015*math.cos(phase*2) if walking else 0
    root=rig.pose.bones['Root']
    root.location=rest_rotations['Root'].inverted() @ to_blender((0,bob,0))
    for side,offset,sign in [('L',0,1),('R',.5,-1)]:
        foot_z,lift=foot_path((progress+offset)%1) if walking else (0,0)
        if walking:
            dy=-.465+lift-(-.355+bob)
            dz=foot_z
            upper=.060;lower=.050
            c=max(-1,min(1,(dy*dy+dz*dz-upper*upper-lower*lower)/(2*upper*lower)))
            knee=math.acos(c)
            hip=math.atan2(-dz,-dy)-math.atan2(lower*math.sin(knee),upper+lower*math.cos(knee))
            hinge('Thigh.'+side,(1,0,0),hip)
            hinge('Shin.'+side,(1,0,0),knee)
            hinge('Foot.'+side,(1,0,0),-hip-knee)
        swing=foot_z/.0365*.23 if walking else 0
        lower_arm=Quaternion(to_blender((0,0,1)),-sign*math.radians(72))
        swing_arm=Quaternion(to_blender((1,0,0)),swing)
        rotate('UpperArm.'+side,swing_arm @ lower_arm)
        hinge('Forearm.'+side,(1,0,0),-.06)
    if walking:
        hinge('Spine',(0,0,1),.012*math.sin(phase))
        hinge('Head',(0,0,1),-.008*math.sin(phase))

scene.render.fps=60
scene.frame_start=1;scene.frame_end=49
rig.animation_data_create()
actions={}
for name,walking in [('Idle',False),('Walk',True)]:
    action=bpy.data.actions.new(name)
    action.use_fake_user=True
    rig.animation_data.action=action
    for frame in range(1,50):
        scene.frame_set(frame)
        progress=(frame-1)/48
        pose(progress,walking)
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=bone.name)
        rig.pose.bones['Root'].keyframe_insert(data_path='location',frame=frame,group='Root')
    actions[name]=action
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,1,action)

# Export the original textured materials. The game supplies its cartoon shader.
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True);rig.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/pet_blender_rigged.glb'),
    export_format='GLB',use_selection=True,export_animations=True,
    export_animation_mode='NLA_TRACKS',export_force_sampling=True,
    export_frame_range=True,export_skins=True,export_def_bones=False,
    export_rest_position_armature=True,export_apply=False)

# Keep the editable .blend visually consistent with the game preview.
for track in rig.animation_data.nla_tracks: track.mute=True
rig.animation_data.action=actions['Walk']
scene.frame_set(7)
for index,source in enumerate(list(mesh.data.materials)):
    bsdf=next(n for n in source.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    links=bsdf.inputs['Base Color'].links
    image=links[0].from_node.image if links and links[0].from_node.type=='TEX_IMAGE' else None
    mat=bpy.data.materials.new('Cartoon '+source.name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
    diffuse=nodes.new('ShaderNodeBsdfDiffuse');diffuse.inputs['Color'].default_value=(1,1,1,1)
    rgb=nodes.new('ShaderNodeShaderToRGB');links.new(diffuse.outputs[0],rgb.inputs[0])
    ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='CONSTANT'
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    for idx,(position,value) in enumerate([(0,.43),(.35,.73),(.70,1.0)]):
        element=ramp.color_ramp.elements[0] if idx==0 else ramp.color_ramp.elements.new(position)
        element.position=position;element.color=(value,value,value,1)
    links.new(rgb.outputs[0],ramp.inputs[0])
    texture=nodes.new('ShaderNodeTexImage');texture.image=image
    multiply=nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
    links.new(texture.outputs['Color'],multiply.inputs[1]);links.new(ramp.outputs[0],multiply.inputs[2])
    emission=nodes.new('ShaderNodeEmission');links.new(multiply.outputs[0],emission.inputs[0])
    output=nodes.new('ShaderNodeOutputMaterial');links.new(emission.outputs[0],output.inputs[0])
    mesh.data.materials[index]=mat

outline=mesh.copy();outline.data=mesh.data.copy();outline.name='Cartoon outline'
scene.collection.objects.link(outline)
for vertex in outline.data.vertices:vertex.co+=Vector(smooth_normals[vertex.index])*.004
for polygon in outline.data.polygons:polygon.flip()
black=bpy.data.materials.new('Dark cartoon outline');black.diffuse_color=(.055,.035,.05,1)
black.use_nodes=True;black.use_backface_culling=True
bsdf=black.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value=(.055,.035,.05,1)
bsdf.inputs['Roughness'].default_value=1
outline.data.materials.clear();outline.data.materials.append(black)
outline.hide_select=True

scene.render.engine='BLENDER_EEVEE_NEXT'
scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.film_transparent=True
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='Standard'
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.4
for name,location,power,size in [('Key',(-2,-3,3),180,3),('Fill',(2,-2,1),65,3)]:
    bpy.ops.object.light_add(type='AREA',location=location)
    light=bpy.context.object;light.name=name;light.data.energy=power;light.data.size=size
    light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.45,-2.15,.0))
camera=bpy.context.object;camera.name='Walking preview';camera.data.type='ORTHO';camera.data.ortho_scale=1.16
camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera=camera
# Default opening state selects the editable armature in pose mode.
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools/pet_rigged_walk.blend'))
scene.render.filepath=str(ROOT/'previews/blender_cartoon_walk.png')
bpy.ops.render.render(write_still=True)
report={'source':'Blender 4.4','bones':[b[0] for b in bones],
        'weighted_vertices':len(mesh.data.vertices),'animations':['Idle','Walk'],
        'walk_duration':.8,'foot_plant':'two-bone leg solve with flat soles',
        'blend':'tools/pet_rigged_walk.blend','glb':'assets/pet_blender_rigged.glb'}
(ROOT/'assets/rig_info.json').write_text(json.dumps(report,indent=2))
print('BLENDER_RIG_WALK_COMPLETE',json.dumps(report))
