extends SceneTree
## Seeded progression: safe combat foundations before pit/wall-jump gauntlets.
var checks := 0
var failures := 0
var failing_seeds: Array = []

func check(ok: bool, label: String, run_seed: int) -> void:
	checks += 1
	if not ok:
		failures += 1
		if not failing_seeds.has(run_seed): failing_seeds.append(run_seed)
		if failures <= 6: printerr("FAIL: ",label," seed=",run_seed)

func _init() -> void:
	var orders: Dictionary = {}
	for run_seed in range(1,129):
		var run := RunModel.new(run_seed)
		var again := RunModel.new(run_seed)
		var tags: Array = []
		for room in run.route: tags.append(str(room.tag))
		orders[str(tags)] = true
		check(tags.size()==8 and tags[0]=="intro" and tags[-1]=="boss","the original eight-room loop is preserved",run_seed)
		check(tags[1] in ["arena","tiers"] and tags[2] in ["arena","tiers"],"safe arena and ascent teach combat before pits",run_seed)
		check(tags[3] in ["gap","platforms"] and tags[4] in ["gap","platforms"],"mid-run introduces the crossing rooms",run_seed)
		check(tags[5] in ["chamber","crossfire"] and tags[6] in ["chamber","crossfire"],"wall-jump and exposed gauntlets belong late",run_seed)
		check(tags.duplicate().size()==8 and {tags[1]:true,tags[2]:true,tags[3]:true,tags[4]:true,tags[5]:true,tags[6]:true}.size()==6,"every combat room appears once",run_seed)
		var repeat: Array = []
		for room in again.route: repeat.append(str(room.tag))
		check(tags==repeat,"route remains seed-reproducible",run_seed)
	check(orders.size()>1,"order still varies within the pacing bands",0)
	print("RUN_PACING_RESULT: %s (%d checks, %d failures, %d route orders, failing seeds=%d)" % ["PASS" if failures==0 else "FAIL",checks,failures,orders.size(),failing_seeds.size()])
	quit(0 if failures==0 else 1)
