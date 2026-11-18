from pathlib import Path
import re, sys
p=Path(sys.argv[1])/'game/world_view.gd';s=p.read_text();s=s.replace('var painter =','var profile_draw={}\nvar profile_process_us=0\nvar profile_draw_us=0\nvar painter =',1)
s=s.replace('func _process(dt):','func _process(dt):\n\tvar profile_start=Time.get_ticks_usec()').replace('\tqueue_redraw()','\tqueue_redraw()\n\tprofile_process_us+=Time.get_ticks_usec()-profile_start',1)
start=s.index('func _draw():');end=s.index('\nfunc ',start);a=s[start:end]
a=a.replace('func _draw():','func _draw():\n\tvar profile_draw_start=Time.get_ticks_usec()\n\tvar profile_section=profile_draw_start\n\tvar profile_label="setup_or_terrain"')
markers={'\tfor nest in sim.world.nests:':'pois','\tfor f in sim.fields:':'fields','\tfor pickup in sim.pickups:':'pickups','\t_prepare_feeding()':'feeding','\tfor fragment in sim.remains:':'remains','\tfor resident in sim.residents:':'residents','\tfor e in sim.enemies:':'enemies','\tif sim.build.rank("division")>0:':'clones','\t_draw_player()':'player','\tfor shot in sim.shots:':'shots','\tfor effect in sim.effects:':'effects','\tdraw_set_transform(Vector2.ZERO)':'labels'}
lines=[];seen=set()
for line in a.splitlines():
 if line in markers and markers[line] not in seen:
  name=markers[line];seen.add(name)
  lines += ['\tprofile_draw[profile_label]=profile_draw.get(profile_label,0)+Time.get_ticks_usec()-profile_section','\tprofile_section=Time.get_ticks_usec()','\tprofile_label="'+name+'"']
 lines.append(line)
lines += ['\tprofile_draw[profile_label]=profile_draw.get(profile_label,0)+Time.get_ticks_usec()-profile_section','\tprofile_draw_us+=Time.get_ticks_usec()-profile_draw_start']
s=s[:start]+'\n'.join(lines)+'\n'+s[end:];p.write_text(s)

p=Path(sys.argv[1])/'game/world_view.gd'
s=p.read_text().replace('var profile_process_us=0','var profile_terrain_us=0\nvar profile_process_us=0')
s=re.sub(r'^\t\t(terrain\.update_world\(.+\))$',r'\t\tvar terrain_start=Time.get_ticks_usec()\n\t\t\1\n\t\tprofile_terrain_us+=Time.get_ticks_usec()-terrain_start',s,flags=re.MULTILINE)
p.write_text(s)
