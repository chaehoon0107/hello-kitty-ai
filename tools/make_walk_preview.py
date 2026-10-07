from pathlib import Path
from PIL import Image,ImageChops

root=Path(__file__).resolve().parents[1]
paths=sorted((root/'previews/walk_frames').glob('frame_*.png'))
assert len(paths)==24
frames=[]
for path in paths:
    image=Image.open(path).convert('RGBA')
    background=Image.new('RGBA',image.size,(245,242,249,255))
    background.alpha_composite(image)
    frames.append(background.convert('RGB'))
assert ImageChops.difference(frames[0],frames[6]).getbbox(), 'The rendered walk must visibly change'
frames[0].save(root/'previews/kitty_walk.gif',save_all=True,append_images=frames[1:],duration=33,loop=0)
sheet=Image.new('RGB',(240*4,256),(245,242,249))
for column,frame in enumerate([0,6,12,18]):sheet.paste(frames[frame],(column*240,0))
sheet.save(root/'previews/kitty_walk_poses.png')
print('Animated walk preview generated from 24 Godot frames')
