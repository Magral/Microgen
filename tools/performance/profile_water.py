"""Profile a disposable copy. Usage: profile_water.py SOURCE OUTPUT; requires Xorg/Godot."""
import pathlib,sys,subprocess,os,socket,time,json,shutil,tempfile
source=pathlib.Path(sys.argv[1]).resolve();out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
project=pathlib.Path(tempfile.mkdtemp(prefix='microgen-water-'))/'project'
shutil.copytree(source,project,ignore=shutil.ignore_patterns('.git','.godot','build','*.zip'))
p=project/'game/fluid_view.gd';s=p.read_text()
s=s.replace('var particles:', 'var profile_update_us=0\nvar profile_draw_us=0\nvar particles:',1)
s=s.replace('func update(dt: float,sim,size: Vector2,view_zoom: float=1.0):','func update(dt: float,sim,size: Vector2,view_zoom: float=1.0):\n\tvar profile_start=Time.get_ticks_usec()',1)
s=s.replace('\tqueue_redraw()','\tqueue_redraw()\n\tprofile_update_us+=Time.get_ticks_usec()-profile_start',1)
s=s.replace('\nfunc _draw():','\nfunc _draw():\n\tvar profile_start=Time.get_ticks_usec()',1)
s+='\n\tprofile_draw_us+=Time.get_ticks_usec()-profile_start\n'
p.write_text(s)
foreground='front=Fluid.Surface.new()\n front.fluid=fluid\n root.add_child(front)' if 'class Surface:' in s else ''
script='''extends SceneTree
const Sim=preload("res://game/simulation.gd")
const Fluid=preload("res://game/fluid_view.gd")
var sim
var fluid
var front: Node2D
var frame=0
var wall=[]
var start=0
func _initialize():
 Engine.max_fps=0
 root.size=Vector2i(1280,720)
 sim=Sim.new()
 sim.new_run(44)
 sim.paused=true
 fluid=Fluid.new()
 root.add_child(fluid)
 FOREGROUND
 fluid.reset(44,sim.player,Vector2(1280,720))
 fluid.clock=12.0
 for i in range(96):fluid.wakes.append({"pos":sim.player+Vector2.from_angle(i*2.399)*(20+i%8*30),"angle":i*2.399,"r":12+i%6*5,"life":1.0})
func _process(_dt):
 if start>0 and frame>60:wall.append(Time.get_ticks_usec()-start)
 start=Time.get_ticks_usec()
 fluid.update(1.0/60,sim,Vector2(1280,720),1.0)
 if is_instance_valid(front):front.queue_redraw()
 frame+=1
 if frame==60:
  fluid.profile_update_us=0
  fluid.profile_draw_us=0
 if frame==241:
  wall.sort()
  var depths=fluid.get("depths")
  print("WATER ",JSON.stringify({"frame_median_us":wall[wall.size()/2],"frame_p95_us":wall[int(wall.size()*0.95)],"update_mean_us":fluid.profile_update_us/181.0,"draw_mean_us":fluid.profile_draw_us/180.0,"particles":fluid.particles.size(),"wakes":fluid.wakes.size(),"depths":depths.size() if depths!=null else 0,"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}))
  quit()
 return false
'''.replace('FOREGROUND',foreground)
(project/'tests/profile_water.gd').write_text(script)
number=next(n for n in range(70,90) if not pathlib.Path('/tmp/.X%d-lock'%n).exists())
config=pathlib.Path(__file__).resolve().parent/'xorg-dummy.conf'
with (out/'water-xorg.log').open('w') as log:
 x=subprocess.Popen(['Xorg',':'+str(number),'-config',str(config),'-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac'],stdout=log,stderr=subprocess.STDOUT)
 try:
  for _ in range(100):
   try:
    with socket.create_connection(('127.0.0.1',6000+number),timeout=.1):break
   except OSError:time.sleep(.1)
  env=os.environ.copy();env['DISPLAY']='127.0.0.1:'+str(number)
  with (out/'water.log').open('w') as log:
   subprocess.run(['godot','--path',str(project),'--rendering-method','gl_compatibility','--audio-driver','Dummy','--disable-vsync','--script','res://tests/profile_water.gd'],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
 finally:x.terminate();x.wait(timeout=5)
print((out/'water.log').read_text())
