"""Rig the user's separated parts, preserving rigid rounded arms and boots."""
import bpy, math, json, bmesh
from pathlib import Path
from mathutils import Vector, Quaternion

ROOT=Path(__file__).resolve().parents[1]
scene=bpy.context.scene
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/pet_smooth_parts.glb'))
parts={int(o.name.split('_')[-1]):o for o in scene.objects if o.type=='MESH'}
# Keep the repaired geometry, UVs and all separated components intact.
names={0:'Head',1:'Bow',2:'Overalls',3:'Arm.L',7:'Arm.R',4:'Boot.L',8:'Boot.R',5:'Tail',
 9:'ShoulderPatch.R',10:'ChestPatch.R',12:'CollarPatch',15:'ChestPatch.L',
 16:'BootPatch.L',11:'BootOuterPatch.R',13:'BootInnerPatch.R',14:'BowPatch'}
for i,obj in parts.items():
    obj.name=names[i]
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    if obj.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in obj.data.polygons:p.use_smooth=True
    for mat in obj.data.materials:
        if not mat or not mat.use_nodes:continue
        for node in mat.node_tree.nodes:
            if node.type=='BSDF_PRINCIPLED':
                for socket in ['Normal','Metallic','Roughness']:
                    for link in list(node.inputs[socket].links):mat.node_tree.links.remove(link)
                node.inputs['Roughness'].default_value=.9
                node.inputs['Metallic'].default_value=0
                node.inputs['Specular IOR Level'].default_value=.22

def to_blender(p):return Vector((p[0],-p[2],p[1]))
bones=[('Root',None,(0,0,0),(0,.08,0)),
 ('Hips','Root',(0,-.335,0),(0,-.27,0)),
 ('Spine','Hips',(0,-.235,0),(0,-.10,0)),
 ('Head','Spine',(0,-.09,0),(0,.30,0))]
for side,sign in [('L',1),('R',-1)]:
    bones.extend([
     ('UpperArm.'+side,'Spine',(sign*.165,-.13,0),(sign*.285,-.13,0)),
     ('Forearm.'+side,'UpperArm.'+side,(sign*.285,-.13,0),(sign*.375,-.13,0)),
     ('Hand.'+side,'Forearm.'+side,(sign*.375,-.13,0),(sign*.41,-.13,0)),
     ('Thigh.'+side,'Hips',(sign*.095,-.355,0),(sign*.095,-.415,0)),
     ('Shin.'+side,'Thigh.'+side,(sign*.095,-.415,0),(sign*.095,-.465,0)),
     ('Foot.'+side,'Shin.'+side,(sign*.095,-.465,0),(sign*.095,-.465,.085))])
arm_data=bpy.data.armatures.new('PetSkeleton')
rig=bpy.data.objects.new('PetRig',arm_data);scene.collection.objects.link(rig)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for name,parent,head,tail in bones:
    b=arm_data.edit_bones.new(name);b.head=to_blender(head);b.tail=to_blender(tail)
    if parent:b.parent=arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True;arm_data.display_type='STICK'
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
assignment={0:'Head',1:'Head',3:'UpperArm.L',7:'UpperArm.R',4:'Foot.L',8:'Foot.R',5:'Hips',
 9:'UpperArm.R',10:'Spine',12:'Spine',15:'Spine',16:'Foot.L',11:'Foot.R',13:'Foot.R',14:'Head'}
for i,obj in parts.items():
    obj.parent=rig;mod=obj.modifiers.new('Anatomical skin','ARMATURE');mod.object=rig
    groups={name:obj.vertex_groups.new(name=name) for name,_,_,_ in bones}
    part_group=obj.vertex_groups.new(name='Part.'+names[i])
    part_group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
    for v in obj.data.vertices:
        if i in [3,7,9]:
            side='L' if i==3 else 'R'
            # Only the yellow sleeve root blends into the torso. The complete
            # white hand/arm retains one shoulder influence and its round shape.
            arm_weight=smooth(.15,.235,abs(v.co.x))
            weights={'Spine':1-arm_weight,'UpperArm.'+side:arm_weight}
        elif i in assignment:weights={assignment[i]:1.0}
        else:
            x,y,z=v.co.x,v.co.z,-v.co.y;side='L' if x>=0 else 'R'
            # The hem follows the rigid boot with a gradual blend up to the
            # pelvis. This keeps the ankle attached without bending the sole.
            leg=(1-smooth(-.407,-.335,y))*smooth(.008,.045,abs(x))
            spine=smooth(-.30,-.19,y)
            weights={'Spine':(1-leg)*spine,'Hips':(1-leg)*(1-spine),
              'Foot.'+side:leg}
        for name,w in weights.items():
            if w>1e-6:groups[name].add([v.index],w,'REPLACE')

# Skin the cut interfaces consistently, then physically weld them. UVs and
# material slots remain per-loop, so the repaired colour textures are retained.
part_counts={names[i]:len(obj.data.vertices) for i,obj in parts.items()}
shared={}
for i,obj in parts.items():
    for v in obj.data.vertices:
        shared.setdefault(tuple(round(c,5) for c in v.co),[]).append((i,obj,v.index))
seam_counts={'L':0,'R':0}
for entries in shared.values():
    owners={i for i,_,_ in entries}
    if len(owners)<2:continue
    if owners & {4,16}:weights={'Foot.L':1.0}
    elif owners & {8,11,13}:weights={'Foot.R':1.0}
    else:
        weights={}
        for i,obj,vi in entries:
            for g in obj.data.vertices[vi].groups:
                name=obj.vertex_groups[g.group].name
                if name not in {b[0] for b in bones}:continue
                weights[name]=weights.get(name,0)+g.weight/len(entries)
        total=sum(weights.values());weights={n:w/total for n,w in weights.items()}
    for i,obj,vi in entries:
        for name,_,_,_ in bones:obj.vertex_groups[name].remove([vi])
        for name,w in weights.items():obj.vertex_groups[name].add([vi],w,'REPLACE')
        for side,part in [('L',3),('R',7)]:
            if part in owners:
                group=obj.vertex_groups.get('Seam.'+side) or obj.vertex_groups.new(name='Seam.'+side)
                group.add([vi],1,'REPLACE')
    for side,part in [('L',3),('R',7)]:
        if part in owners:seam_counts[side]+=1
assert min(seam_counts.values())>=10,seam_counts
bpy.ops.object.select_all(action='DESELECT')
for obj in parts.values():obj.select_set(True)
body=parts[2];bpy.context.view_layer.objects.active=body;bpy.ops.object.join()
body.name='KittyJoinedMesh'
bm=bmesh.new();bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00008)
bm.to_mesh(body.data);bm.free();body.data.update()
parts_for_export=[body]
boot_indices={side:[v.index for v in body.data.vertices if any(g.group==body.vertex_groups['Part.Boot.'+side].index and g.weight>.5 for g in v.groups)] for side in ['L','R']}
seam_indices={side:[v.index for v in body.data.vertices if any(g.group==body.vertex_groups['Seam.'+side].index and g.weight>.5 for g in v.groups)] for side in ['L','R']}
assert all(len(indices)>=10 for indices in seam_indices.values())

rest={b.name:b.matrix_local.to_quaternion() for b in arm_data.bones}
for b in rig.pose.bones:b.rotation_mode='QUATERNION'
def rotate(name,q):rig.pose.bones[name].rotation_quaternion=rest[name].inverted() @ q @ rest[name]
def hinge(name,axis,angle):rotate(name,Quaternion(to_blender(axis),angle))
def foot_path(p):
    stride=.0365
    if p<.5:return stride*(1-4*p),0
    u=(p-.5)*2
    z=(2*u**3-3*u*u+1)*(-stride)+(u**3-2*u*u+u)*(-2*stride)+(-2*u**3+3*u*u)*stride+(u**3-u*u)*(-2*stride)
    return z,.018*math.sin(math.pi*u)**2
def pose(p,walking,motion='Idle'):
    phase=2*math.pi*p
    for b in rig.pose.bones:b.location=(0,0,0);b.rotation_quaternion=(1,0,0,0)
    # Constant root height prevents bobbing and Idle/Walk height changes.
    bob=-.009
    rig.pose.bones['Root'].location=rest['Root'].inverted() @ to_blender((0,bob,0))
    for side,offset,sign in [('L',0,1),('R',.5,-1)]:
        z,lift=foot_path((p+offset)%1) if walking else (0,0)
        dy=-.465+lift-(-.355+bob);upper=.060;lower=.050
        c=max(-1,min(1,(dy*dy+z*z-upper*upper-lower*lower)/(2*upper*lower)))
        knee=math.acos(c)
        hip=math.atan2(-z,-dy)-math.atan2(lower*math.sin(knee),upper+lower*math.cos(knee))
        hinge('Thigh.'+side,(1,0,0),hip);hinge('Shin.'+side,(1,0,0),knee)
        hinge('Foot.'+side,(1,0,0),-hip-knee)
        # One shoulder influence per complete arm prevents angular elbow skinning.
        down=Quaternion(to_blender((0,0,1)),-sign*math.radians(50))
        swing=Quaternion(to_blender((1,0,0)),z/.0365*.27 if walking else 0)
        rotate('UpperArm.'+side,swing @ down)
    if motion=='Think':
        # Keep the welded shoulder and round arm as one continuous influence.
        # The chibi hands move towards the chin and across the waist.
        for side,sign,down_angle,forward in [('L',1,35,100),('R',-1,-12,76)]:
            down=Quaternion(to_blender((0,0,1)),-sign*math.radians(down_angle))
            front=Quaternion(to_blender((0,1,0)),-sign*math.radians(forward+2*math.sin(phase)))
            rotate('UpperArm.'+side,front @ down)
        hinge('Head',(0,0,1),math.radians(2+math.sin(phase)))
    elif motion=='Notice':
        hinge('Head',(0,0,1),math.radians(2*math.sin(phase)))
scene.render.fps=60;scene.frame_start=0;scene.frame_end=48
rig.animation_data_create();actions={}
for name,walking in [('Idle',False),('Walk',True),('Think',False),('Notice',False)]:
    action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
    for frame in range(49):
        scene.frame_set(frame);pose(frame/48,walking,name)
        for b in rig.pose.bones:b.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=b.name)
        rig.pose.bones['Root'].keyframe_insert(data_path='location',frame=frame,group='Root')
    actions[name]=action;rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,0,action)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
for obj in parts_for_export:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/pet_blender_rigged.glb'),export_format='GLB',
 use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,
 export_frame_range=True,export_skins=True,export_def_bones=False,export_rest_position_armature=True,export_apply=False)
for track in rig.animation_data.nla_tracks:track.mute=True
stance_errors=[]
base_areas=[]
for polygon in body.data.polygons:
    a,b,c=[body.data.vertices[vi].co for vi in polygon.vertices[:3]]
    base_areas.append((b-a).cross(c-a).length)
minimum_area_ratio=1.0
minimum_surface_height=1.0
for sample in range(49*len(actions)):
    name=list(actions)[sample//49]
    rig.animation_data.action=actions[name]
    frame=sample%49
    scene.frame_set(frame);bpy.context.view_layer.update()
    p=frame/48 if name=='Walk' else 0
    evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    minimum_surface_height=min(minimum_surface_height,min((evaluated.matrix_world @ v.co).z for v in evaluated.data.vertices))
    for polygon,base_area in zip(evaluated.data.polygons,base_areas):
        if base_area<1e-8:continue
        a,b,c=[evaluated.data.vertices[vi].co for vi in polygon.vertices[:3]]
        minimum_area_ratio=min(minimum_area_ratio,(b-a).cross(c-a).length/base_area)
    for side,part,offset in [('L',4,0),('R',8,.5)]:
        if (p+offset)%1>.5:continue
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        minimum=min((evaluated.matrix_world @ evaluated.data.vertices[vi].co).z for vi in boot_indices[side])
        stance_errors.append(abs(minimum+.48901367))
assert max(stance_errors)<.0001,('Planted soles must stay on the plane',max(stance_errors))
assert minimum_area_ratio>.02,('A triangle collapsed during the walk',minimum_area_ratio)
assert minimum_surface_height>-.4892,('The mesh extends through the floor',minimum_surface_height)
rig.animation_data.action=actions['Walk'];scene.frame_set(6)
# Display only the supplied colour texture in the editable Blender preview.
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if not bsdf:continue
    links=list(bsdf.inputs['Base Color'].links)
    image=links[0].from_node.image if links and links[0].from_node.type=='TEX_IMAGE' else None
    color=tuple(bsdf.inputs['Base Color'].default_value)
    nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
    emission=nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=color
    if image:
        texture=nodes.new('ShaderNodeTexImage');texture.image=image
        links.new(texture.outputs['Color'],emission.inputs['Color'])
    output=nodes.new('ShaderNodeOutputMaterial');links.new(emission.outputs[0],output.inputs[0])
scene.render.engine='BLENDER_EEVEE_NEXT'
scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='Standard'
bpy.ops.object.camera_add(location=(0,-3,0));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=1.16
camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools/pet_rigged_walk.blend'))
scene.render.filepath=str(ROOT/'previews/blender_unshaded_walk.png');bpy.ops.render.render(write_still=True)
report={'source':'user separated GLB','bones':[b[0] for b in bones],
 'parts':part_counts,'joined_mesh':body.name,'welded_shoulder_vertices':seam_counts,
 'rigid_parts':{names[i]:bone for i,bone in assignment.items() if i not in [3,7,9]},'animations':list(actions),
 'walk_duration':.8,'shading':'unshaded, repaired original textures',
 'planted_sole_max_error':max(stance_errors),'body_height':'constant',
 'minimum_triangle_area_ratio':minimum_area_ratio,'minimum_surface_height':minimum_surface_height,
 'blend':'tools/pet_rigged_walk.blend','glb':'assets/pet_blender_rigged.glb'}
(ROOT/'assets/rig_info.json').write_text(json.dumps(report,indent=2))
print('SEPARATED_PART_RIG_COMPLETE',json.dumps(report))
