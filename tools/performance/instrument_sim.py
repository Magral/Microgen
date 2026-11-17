from pathlib import Path
import sys
p=Path(sys.argv[1])/'game/simulation.gd'
s=p.read_text().replace('var feedback: Array=[]','var profile_times={}\nvar feedback: Array=[]')
start=s.index('func step(');end=s.index('\nfunc _reveal',start)
a=s[start:end]
for name in ['_reveal','_spawn_wave','_check_nests','_update_ecology','_update_minibosses','_update_enemies','_attack','_update_shots','_update_fields','_update_remains','_collect']:
 lines=a.splitlines();out=[]
 for line in lines:
  if line.strip().startswith(name+'('):
   indent=line[:len(line)-len(line.lstrip())]
   out += [indent+'var profile_start_'+name+'=Time.get_ticks_usec()',line,indent+'profile_times["'+name+'"] = profile_times.get("'+name+'",0)+Time.get_ticks_usec()-profile_start_'+name]
  else:out.append(line)
 a='\n'.join(out)+'\n'
s=s[:start]+a+s[end:];p.write_text(s)
