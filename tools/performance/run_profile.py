#!/usr/bin/env python3
"""Profile disposable copies; never instrument the source checkout in place."""
import argparse, os, pathlib, re, shutil, socket, subprocess, tarfile, tempfile, time
HERE = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=pathlib.Path, default=HERE.parents[1])
parser.add_argument('--commit', help='Archive this git revision instead of the working tree')
parser.add_argument('--output', type=pathlib.Path, required=True)
parser.add_argument('--snapshots', type=pathlib.Path, help='Use another replay output for identical native scenes')
parser.add_argument('--render-only', action='store_true', help='Skip the replay; requires --native and --snapshots')
parser.add_argument('--native', action='store_true', help='Also benchmark actual native rendering')
parser.add_argument('--pova-size', action='store_true', help='Render on a 2460×1080 window with identical expanded canvas on both revisions')
parser.add_argument('--mobile-profile', action='store_true', help='Use the Android world render buffer on a desktop')
parser.add_argument('--stress-only', action='store_true', help='Render only the fixed stress scene')
parser.add_argument('--terrain-raster', action='store_true', help='Compare vector and raster terrain only on the same wide native scene')
parser.add_argument('--display', help='Existing X11 display; otherwise start local Xorg dummy over TCP')
parser.add_argument('--godot', default='godot')
args = parser.parse_args()
if args.render_only and not (args.native and args.snapshots):
    parser.error('--render-only requires --native and --snapshots')
if args.terrain_raster and not args.native:
    parser.error('--terrain-raster requires --native')
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
work = pathlib.Path(tempfile.mkdtemp(prefix='microgen-profile-'))
project = work/'project'
project.mkdir()
if args.commit:
    archive = work/'source.tar'
    with archive.open('wb') as stream:
        subprocess.run(['git', '-C', str(args.source), 'archive', args.commit], stdout=stream, check=True)
    with tarfile.open(archive) as bundle:
        bundle.extractall(project, filter='data')
else:
    shutil.copytree(args.source, project, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.git', '.godot', 'build', '*.zip'))
(project/'tests').mkdir(exist_ok=True)
for script in HERE.glob('profile_*.gd'):
    shutil.copy2(script, project/'tests'/script.name)
for script in ['instrument_sim.py', 'instrument_view.py']:
    subprocess.run(['python', str(HERE/script), str(project)], check=True)
env = os.environ.copy()
env['MICROGEN_PROFILE_OUTPUT'] = str(args.output)
if args.pova_size:
    env['MICROGEN_POVA_SIZE'] = '1'
if args.mobile_profile:
    env['MICROGEN_MOBILE_PROFILE'] = '1'
base = [args.godot, '--path', str(project)]
def run(script, log, native=False):
    command = base + (['--rendering-method','gl_compatibility','--audio-driver','Dummy','--disable-vsync'] if native else ['--headless']) + ['--script', 'res://tests/'+script]
    with (args.output/log).open('w') as stream:
        subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)
    if re.search(r"(?m)^(?:SCRIPT ERROR:|ERROR:)", (args.output/log).read_text()):
        raise RuntimeError("Godot reported an error: " + str(args.output/log))
if not args.render_only and not args.terrain_raster:
    run('profile_long.gd', 'simulation.log')
xorg = None
try:
    if args.native:
        if args.snapshots:
            env['MICROGEN_PROFILE_OUTPUT'] = str(args.snapshots.resolve())
        if args.display:
            env['DISPLAY'] = args.display
        else:
            # TCP keeps Xorg and Godot in the same sandbox; no shared Unix socket needed.
            display = next(n for n in range(70, 90) if not pathlib.Path('/tmp/.X%d-lock'%n).exists())
            config = HERE/'xorg-dummy.conf'
            xlog = (args.output/'xorg.log').open('w')
            xorg = subprocess.Popen(['Xorg', ':'+str(display), '-config', str(config), '-noreset', '-nolisten','unix','-nolisten','local','-listen','tcp','-ac'], stdout=xlog, stderr=subprocess.STDOUT)
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1', 6000+display), timeout=.1): break
                except OSError: time.sleep(.1)
            else: raise RuntimeError('Xorg failed to become ready; inspect xorg.log or supply --display')
            env['DISPLAY'] = '127.0.0.1:'+str(display)
        if args.terrain_raster:
            run('profile_terrain_raster.gd', 'terrain.log', True)
        else:
            if not args.stress_only:
                run('profile_render.gd', 'native.log', True)
            run('profile_worst.gd', 'worst.log', True)
finally:
    if xorg:
        xorg.terminate()
        xorg.wait(timeout=5)
print('Evidence:', args.output)
print('Disposable instrumented project:', project)
