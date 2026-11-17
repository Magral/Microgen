extends SceneTree
const Stats=preload("res://core/combat_stats.gd")
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize():
	var stats=Stats.create()
	Stats.record_damage(stats,"spike",12.5)
	Stats.record_damage(stats,"spike",0.0)
	Stats.record_damage(stats,"spike",-4.0)
	Stats.record_kill(stats,"spike")
	Stats.record_heal(stats,3.5)
	check(stats.damage_dealt==12.5 and stats.organs.spike.hits==1 and stats.organs.spike.kills==1,"actual outgoing damage, hits and kills")
	check(stats.kills_by_source.spike==1 and stats.healed==3.5,"kill and actual healing totals")
	for i in range(100): Stats.record_taken(stats,float(i)*0.1,0.2,0.05,"toxin","Кислотное облако",Vector2(i,4),7)
	check(is_equal_approx(stats.damage_taken,20.0) and is_equal_approx(stats.blocked,5.0),"continuous cloud damage sums actual health changes")
	check(stats.history.size()==1 and is_equal_approx(stats.history[0].amount,20.0),"continuous same-source cloud ticks aggregate")
	check(stats.history[0].pos==[99.0,4.0],"aggregate retains latest hit position")
	Stats.record_taken(stats,10,2,0,"toxin","Кислотное облако",Vector2.ZERO,8)
	check(stats.history.size()==2,"different source identities stay separate")
	Stats.record_taken(stats,11,0,6,"collision","",Vector2.ZERO,0)
	check(stats.blocked>10 and stats.history.size()==2,"fully blocked hit contributes mitigation without fake damage history")
	var unknown=Stats.record_taken(stats,12,3,0,"","",Vector2.ZERO,0)
	check(unknown.kind=="unknown" and not unknown.name.is_empty(),"unknown damage remains visible")
	Stats.record_taken(stats,14,1,0,"","",Vector2.ZERO,0)
	check(stats.history.size()==4,"separated same-source hits do not aggregate")
	for i in range(60): Stats.record_taken(stats,20+i*2,1,0,"collision","Enemy %d" % i,Vector2.ZERO,i)
	check(stats.history.size()==32,"damage history bounded to 32")
	var restored=Stats.restore(JSON.parse_string(JSON.stringify(stats)))
	check(restored.history.size()==32 and is_equal_approx(restored.damage_taken,stats.damage_taken) and restored.organs==stats.organs,"JSON restore keeps history and attribution")
	var clean=Stats.restore({"damage_taken":-1,"blocked":"oops","history":[{"amount":-4},{"amount":3,"pos":["bad",null]}],"organs":{"x":{"damage":-2,"kills":-3}},"sources":{"x":{"damage":-2}}})
	check(clean.damage_taken==0 and clean.blocked==0 and clean.healed==0,"old and malformed save totals sanitized")
	check(clean.history.size()==1 and clean.history[0].pos==[0.0,0.0] and clean.organs.x.kills==0 and clean.sources.values()[0].damage==0,"malformed history and source counters sanitized")
	check(Stats.restore(null)==Stats.create(),"missing legacy stats get defaults")
	var repeated=Stats.create()
	for i in range(1000): Stats.record_taken(repeated,i*0.1,2,0,"collision","Хищник",Vector2.ZERO,i)
	check(repeated.sources.size()==1 and repeated.sources.values()[0].damage==2000 and repeated.sources.values()[0].hits==1000,"thousand actor IDs use one source type bucket")
	check(repeated.history.size()==32 and repeated.history.back().source_id==999 and repeated.history[-2].source_id==998,"history retains actor identities separately")
	var unique=Stats.create()
	var legacy_sources={}
	for i in range(1000):
		Stats.record_taken(unique,i,2,0,"collision","Custom %d" % i,Vector2.ZERO,i)
		legacy_sources["collision:%d:Custom %d" % [i,i]]={"kind":"collision","name":"Custom %d" % i,"source_id":i,"damage":2,"hits":1}
	var summary_damage=0.0
	var summary_hits=0
	for bucket in unique.sources.values():
		summary_damage+=bucket.damage
		summary_hits+=bucket.hits
	check(unique.sources.size()==33 and unique.sources[Stats.OTHER_SOURCE_KEY].name=="Прочие источники","custom source names capped with one explicit overflow bucket")
	check(summary_damage==2000 and summary_hits==1000,"overflow preserves all source damage and hits")
	var compacted=Stats.restore({"sources":legacy_sources})
	check(compacted.sources==unique.sources,"restore compacts old actor keys with source cap and conserves totals")
	check(Stats.restore(JSON.parse_string(JSON.stringify(unique))).sources==unique.sources,"overflow summary survives JSON restore without extra bucket")
	var old_repeated={}
	for i in range(1000): old_repeated[str(i)]={"kind":"collision","name":"Хищник","source_id":i,"damage":2,"hits":1}
	check(Stats.restore({"sources":old_repeated}).sources==repeated.sources,"restore merges old actor IDs into one source type")
	print("COMBAT STATS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
