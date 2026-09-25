class_name Save
extends RefCounted
## Persistent save: cells (meta currency), best score, purchased meta upgrades,
## options, bindings and the ledger of finished descents. Stored as JSON at
## user://graveflame_save.json. Dead Cells-style meta progression.
## The parsed file is cached, so reads never touch the disk, and every write is
## atomic, so a crash mid-write can never wipe progress.

const SAVE_PATH := "user://graveflame_save.json"
## Finished descents the ledger keeps, newest first.
const HISTORY_CAP := 12
## Active file. Tests and tooling point this at a scratch file so simulated runs
## never touch the player's real progress. Pointing it elsewhere drops the cache.
static var path := SAVE_PATH:
	set(value):
		path = value
		_cache = {}
## The parsed save at `path`; empty until first read.
static var _cache: Dictionary = {}

## A private copy of the save, for callers that edit it and hand it to save_save.
static func load_save() -> Dictionary:
	return _data().duplicate(true)

## The cached save, read from disk once. Getters only read it; mutators edit it
## in place and then _write it.
static func _data() -> Dictionary:
	if _cache.is_empty():
		_cache = _coerced(_read_with_fallback())
	return _cache

## The file at `path`, or the copy the last good write left beside it when the
## file is torn. If both are unreadable the damaged file is kept aside, so the
## defaults that take over never silently destroy it. A missing file is a fresh
## start, not damage: a deleted save stays deleted.
static func _read_with_fallback() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = _parse(path)
	if d == null:
		d = _parse(path + ".bak")
		if d == null:
			DirAccess.copy_absolute(path, "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())])
			return {}
	return d

## The JSON dictionary in `file`, or null when it is missing, unparseable or not
## a dictionary. An empty dictionary is a valid (fresh) save, not damage.
static func _parse(file: String) -> Variant:
	var json := JSON.new()
	if not FileAccess.file_exists(file) or json.parse(FileAccess.get_file_as_string(file)) != OK:
		return null
	return json.data if json.data is Dictionary else null

## Hand-edited or older files must still carry the core keys with sane types.
static func _coerced(d: Dictionary) -> Dictionary:
	d["cells"] = int(d.get("cells", 0))
	d["best_score"] = int(d.get("best_score", 0))
	for key in ["meta", "learned"]:
		if not (d.get(key) is Array):
			d[key] = []
	return d

static func save_save(data: Dictionary) -> void:
	_cache = _coerced(data.duplicate(true))
	_write()

## Writes the cache to a temporary file, keeps the current file as `.bak`, then
## renames the new one over it. The rename is atomic, so the file on disk is
## always either the old save or the new one, never half of each.
static func _write() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null or not f.store_string(JSON.stringify(_cache, "  ")):
		push_warning("Save: could not write to %s" % tmp)
		return
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_warning("Save: could not replace %s" % path)

## The container stored under `key`, reset to `empty` when it is missing or
## of the wrong type, so a mutator can edit it in place.
static func _slot(key: String, empty: Variant) -> Variant:
	var d := _data()
	if typeof(d.get(key)) != typeof(empty):
		d[key] = empty
	return d[key]

## Bank `amount` cells and return the new total.
static func add_cells(amount: int) -> int:
	_data()["cells"] = get_cells() + amount
	_write()
	return get_cells()

static func get_cells() -> int:
	return int(_data()["cells"])

static func get_best_score() -> int:
	return int(_data()["best_score"])

## Player options. Volumes are linear 0..1; everything else is a bool. These
## live in the same save file so accessibility choices survive a relaunch.
const DEFAULT_OPTIONS := {
	"master": 0.9, "music": 0.75, "sfx": 0.9, "music_on": true,
	"fullscreen": false, "reduced_motion": false, "reduced_flash": false,
	"vibration": true, "shake": 1.0,
}

## Forget every rebinding, so the project's default keys return on next boot.
static func clear_bindings() -> void:
	var d := load_save()
	d.erase("bindings")
	save_save(d)

## Player key rebindings, stored as action -> physical keycode. Only actions in
## Content.CONTROLS_ROWS are honoured, so a hand-edited save cannot invent an
## action or clobber a menu binding.
static func get_bindings() -> Dictionary:
	var stored = _data().get("bindings", {})
	var out := {}
	if not (stored is Dictionary):
		return out
	var known := {}
	for row in Content.CONTROLS_ROWS:
		known[str(row.action)] = true
	for action in stored:
		if known.has(action):
			out[action] = int(stored[action])
	return out

static func set_binding(action: String, keycode: int) -> void:
	(_slot("bindings", {}) as Dictionary)[action] = keycode
	_write()

## Hints the player has already been shown. Kept per-save so a new player is
## taught once, and a returning one is never interrupted again.
static func get_learned_hints() -> Array:
	return (_data()["learned"] as Array).duplicate()

static func has_learned(id: String) -> bool:
	return (_data()["learned"] as Array).has(id)

static func mark_learned(id: String) -> void:
	if has_learned(id):
		return
	(_data()["learned"] as Array).append(id)
	_write()

static func get_options() -> Dictionary:
	var stored = _data().get("options", {})
	var out := DEFAULT_OPTIONS.duplicate()
	if stored is Dictionary:
		for key in out:
			if (stored as Dictionary).has(key):
				out[key] = (stored as Dictionary)[key]
	# Coerce: a hand-edited or older file must never poison the audio server.
	for key in ["master", "music", "sfx", "shake"]:
		out[key] = clampf(float(out[key]), 0.0, 1.0)
	for key in ["fullscreen", "reduced_motion", "reduced_flash", "music_on", "vibration"]:
		out[key] = bool(out[key])
	return out

static func set_option(key: String, value: Variant) -> void:
	(_slot("options", {}) as Dictionary)[key] = value
	_write()

static func get_purchased_meta() -> Array:
	return (_data()["meta"] as Array).duplicate()

## Ranks are stored as repeated ids, so a save from before ranks existed reads
## as rank 1 of everything it bought.
static func get_meta_rank(id: String) -> int:
	return (_data()["meta"] as Array).count(id)

static func purchase_meta(id: String) -> bool:
	var def := Content.meta_def(id)
	if def.is_empty():
		return false
	var cost := Content.meta_next_cost(def, get_meta_rank(id))
	if cost < 0:
		return false
	if get_cells() < cost:
		return false
	_data()["cells"] = get_cells() - cost
	(_data()["meta"] as Array).append(id)
	_write()
	return true

## Returns a build-dict delta from all purchased meta upgrades, applied at run start.
static func get_meta_modifiers() -> Dictionary:
	var out := {"max_hp": 0.0, "speed_mul": 0.0, "dmg_mul": 0.0, "flask": 0, "special_start": 0.0,
		"start_boon": false, "offer_count": 0, "cell_mul": 0.0}
	for id in get_purchased_meta():
		var u := Content.meta_def(str(id))
		if u.is_empty():
			continue
		match str(u.kind):
			"max_hp": out.max_hp += float(u.value)
			"speed_mul": out.speed_mul += float(u.value)
			"dmg_mul": out.dmg_mul += float(u.value)
			"flask": out.flask += int(u.value)
			"special_start": out.special_start = minf(Content.P_SPECIAL_MAX, float(out.special_start) + float(u.value))
			"start_boon": out.start_boon = true
			"offer_count": out.offer_count = mini(int(out.offer_count) + int(u.value), 2)
			"cell_mul": out.cell_mul += float(u.value)
	return out

## Vows currently sworn (ids from Content.VOWS).
static func get_vows() -> Array:
	var v = _data().get("vows", [])
	var out: Array = []
	if v is Array:
		for id in v:
			for def in Content.VOWS:
				if str(def.id) == str(id) and not out.has(str(id)):
					out.append(str(id))
	return out

static func set_vow(id: String, sworn: bool) -> void:
	var arr: Array = get_vows()
	if sworn and not arr.has(id):
		arr.append(id)
	elif not sworn:
		arr.erase(id)
	_data()["vows"] = arr
	_write()

static func get_victories() -> int:
	return int(_data().get("victories", 0))

## Record a won descent and the most vows it has been won under.
static func add_victory(vows_kept: int) -> void:
	var d := _data()
	d["victories"] = int(d.get("victories", 0)) + 1
	d["best_vows"] = maxi(int(d.get("best_vows", 0)), vows_kept)
	_write()

static func vows_unlocked() -> bool:
	return get_victories() > 0

## Fold one finished descent into the ledger with a single write: lifetime
## totals, personal records, the best score, a short history and the boons that
## won. `summary` carries won, seed, room (chambers cleared), score, time,
## kills, cells, streak, heat (vows sworn) and boons (ids taken). Returns
## {broken: [record keys]}, the records this run beat, so the end screen can
## call them out; a record set for the first time beats nothing.
static func record_run(summary: Dictionary) -> Dictionary:
	var won := bool(summary.won)
	var totals: Dictionary = _slot("stats", {})
	var tally := {
		"runs": 1, "wins": int(won), "deaths": int(not won), "kills": summary.kills,
		"cells_earned": summary.cells, "seconds": summary.time,
	}
	for key in tally:
		totals[key] = totals.get(key, 0) + tally[key]
	var candidates := {"best_streak": summary.streak, "deepest_room": summary.room}
	if won:
		candidates.merge({"fastest_win": summary.time, "best_win_score": summary.score, "best_heat": summary.heat})
	var records: Dictionary = _slot("records", {})
	var broken: Array = []
	for key in candidates:
		var value := float(candidates[key])
		if _improves(records, key, value):
			if records.has(key):
				broken.append(key)
			records[key] = value
	_data()["best_score"] = maxi(get_best_score(), int(summary.score))
	var history: Array = _slot("history", [])
	var entry := summary.duplicate()
	entry["date"] = Time.get_date_string_from_system()
	history.push_front(entry)
	history.resize(mini(history.size(), HISTORY_CAP))
	if won:
		var boon_wins: Dictionary = _slot("boon_wins", {})
		for id in summary.boons:
			boon_wins[id] = int(boon_wins.get(id, 0)) + 1
	_write()
	return {"broken": broken}

## Whether `value` improves on the stored record `key`. Every record is a
## high-water mark except the fastest win, which improves downward.
static func _improves(records: Dictionary, key: String, value: float) -> bool:
	if not records.has(key):
		return true
	var old := float(records[key])
	return value < old if key == "fastest_win" else value > old
# --- The finale's legacy ---
## A victory is recorded once, at the killing blow, so quitting, skipping or
## crashing mid-finale never loses it. Deaths are counted because the ending
## raises one fallen knight for every knight ever lost. The choice made at the
## throne is written the moment it is made, and the next descent remembers it.

## How a won descent can end: the crown taken, the flames given back, the
## throne put out for good.
const ENDINGS := ["crown", "given", "ended"]

## Vow counts kept per victory, newest last; the oldest fall off past this.
const ROLL_CAP := 64

## One write at boot, and only for a save that predates the death count: its
## earlier deaths are unknowable, so falls_legacy marks the count as partial.
static func migrate_falls() -> void:
	var d := load_save()
	if d.has("falls"):
		return
	var victories := int(d.get("victories", 0))
	var progressed: bool = int(d.cells) > 0 or int(d.best_score) > 0 or victories > 0
	d["falls"] = 0
	d["falls_legacy"] = progressed or not (d.meta as Array).is_empty() or not (d.learned as Array).is_empty()
	var roll: Array = []
	roll.resize(mini(victories, ROLL_CAP))
	roll.fill(0)
	d["roll"] = roll
	save_save(d)

## A death: count it and keep the epitaph it was shown, for the ending to answer.
static func record_fall(epitaph: String) -> void:
	var d := load_save()
	d["falls"] = int(d.get("falls", 0)) + 1
	d["last_epitaph"] = epitaph
	save_save(d)

## The single save write for a won descent. Returns what the finale needs:
## first, victories, falls_total (every knight ever lost), unknown (a save
## from before the count with no counted fall yet), last_epitaph,
## finale_seen (before this one), milestone ("oath" the first time all five
## vows are kept, else ""), oath_first and last_ending (how the previous won
## descent ended).
static func record_victory(vows: Array) -> Dictionary:
	var d := load_save()
	var victories := int(d.get("victories", 0)) + 1
	var falls := int(d.get("falls", 0))
	var seen := int(d.get("finale_seen", 0))
	var oath := vows.size() == Content.VOWS.size()
	var oath_first := oath and not bool(d.get("oath_kept", false))
	var roll: Array = d.get("roll", [])
	roll.append(vows.size())
	var kept: Array = d.get("vows_kept_ever", [])
	for v in vows:
		if not kept.has(v):
			kept.append(v)
	var out := {
		"first": victories == 1, "victories": victories,
		"falls_total": falls,
		"unknown": bool(d.get("falls_legacy", false)) and falls == 0,
		"last_epitaph": str(d.get("last_epitaph", "")), "finale_seen": seen,
		"milestone": "oath" if oath_first else "", "oath_first": oath_first,
		"last_ending": get_last_ending(),
	}
	d["victories"] = victories
	d["best_vows"] = maxi(int(d.get("best_vows", 0)), vows.size())
	d["last_epitaph"] = ""
	d["finale_seen"] = seen + 1
	d["roll"] = roll.slice(maxi(0, roll.size() - ROLL_CAP))
	d["vows_kept_ever"] = kept
	d["oath_kept"] = bool(d.get("oath_kept", false)) or oath
	save_save(d)
	return out

static func get_falls() -> int:
	return int(_data().get("falls", 0))

static func falls_legacy() -> bool:
	return bool(_data().get("falls_legacy", false))

static func get_roll() -> Array:
	var roll = _data().get("roll", [])
	return (roll as Array).map(func(n): return int(n)) if roll is Array else []

static func get_vows_kept_ever() -> Array:
	var kept = _data().get("vows_kept_ever", [])
	return (kept as Array).duplicate() if kept is Array else []

static func oath_kept() -> bool:
	return bool(_data().get("oath_kept", false))

static func get_finale_seen() -> int:
	return int(_data().get("finale_seen", 0))

## The victory count the title screen last celebrated with a new candle.
static func get_last_celebrated() -> int:
	return int(_data().get("last_celebrated", 0))

static func set_last_celebrated(victories: int) -> void:
	var d := load_save()
	d["last_celebrated"] = victories
	save_save(d)

## "" until a won descent has ended by the knight's choice.
static func get_last_ending() -> String:
	var ending := str(_data().get("last_ending", ""))
	return ending if ENDINGS.has(ending) else ""

## The choice at the throne: the last ending, every ending ever seen, and
## whether the keep was ever put out (the title keeps that dawn for good).
static func set_last_ending(ending: String) -> void:
	if not ENDINGS.has(ending):
		return
	var seen: Array = _slot("endings_seen", [])
	if not seen.has(ending):
		seen.append(ending)
	_data()["last_ending"] = ending
	_data()["ended_ever"] = ended_ever() or ending == "ended"
	_write()

static func get_endings_seen() -> Array:
	var seen = _data().get("endings_seen", [])
	return (seen as Array).filter(func(e): return ENDINGS.has(e)) if seen is Array else []

static func ended_ever() -> bool:
	return bool(_data().get("ended_ever", false))
