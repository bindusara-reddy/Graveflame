class_name Save
extends RefCounted
## Persistent save: cells (meta currency), best score, purchased meta upgrades.
## Stored as JSON at user://graveflame_save.json. Dead Cells-style meta progression.

const SAVE_PATH := "user://graveflame_save.json"
## Active file. Tests and tooling point this at a scratch file so simulated runs
## never touch the player's real progress.
static var path := SAVE_PATH

static func load_save() -> Dictionary:
	var defaults := {"cells": 0, "best_score": 0, "meta": [], "learned": []}
	if not FileAccess.file_exists(path):
		return defaults
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return defaults
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return defaults
	var res: Variant = JSON.parse_string(text)
	if res == null or not (res is Dictionary):
		return defaults
	var d: Dictionary = res
	# Validate / coerce
	d["cells"] = int(d.get("cells", 0))
	d["best_score"] = int(d.get("best_score", 0))
	if not (d.get("meta") is Array):
		d["meta"] = []
	if not (d.get("learned") is Array):
		d["learned"] = []
	return d

static func save_save(data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Save: could not write to %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

static func add_cells(amount: int) -> void:
	var d := load_save()
	d["cells"] = int(d["cells"]) + amount
	save_save(d)

static func spend_cells(amount: int) -> bool:
	var d := load_save()
	if int(d["cells"]) < amount:
		return false
	d["cells"] = int(d["cells"]) - amount
	save_save(d)
	return true

static func get_cells() -> int:
	return int(load_save().get("cells", 0))

static func get_best_score() -> int:
	return int(load_save().get("best_score", 0))

static func set_best_score(s: int) -> void:
	var d := load_save()
	if s > int(d.get("best_score", 0)):
		d["best_score"] = s
		save_save(d)

## Player options. Volumes are linear 0..1; everything else is a bool. These
## live in the same save file so accessibility choices survive a relaunch.
const DEFAULT_OPTIONS := {
	"master": 0.9, "music": 0.75, "sfx": 0.9, "music_on": true,
	"fullscreen": false, "reduced_motion": false, "reduced_flash": false,
}

## Player key rebindings, stored as action -> physical keycode. Only actions in
## Content.CONTROLS_ROWS are honoured, so a hand-edited save cannot invent an
## action or clobber a menu binding.
static func get_bindings() -> Dictionary:
	var stored = load_save().get("bindings", {})
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
	var d := load_save()
	var b = d.get("bindings", {})
	if not (b is Dictionary):
		b = {}
	(b as Dictionary)[action] = keycode
	d["bindings"] = b
	save_save(d)

## Hints the player has already been shown. Kept per-save so a new player is
## taught once, and a returning one is never interrupted again.
static func get_learned_hints() -> Array:
	var m = load_save().get("learned", [])
	return m if m is Array else []

static func has_learned(id: String) -> bool:
	return get_learned_hints().has(id)

static func mark_learned(id: String) -> void:
	if has_learned(id):
		return
	var d := load_save()
	var arr: Array = d.get("learned", [])
	if not (arr is Array):
		arr = []
	arr.append(id)
	d["learned"] = arr
	save_save(d)

static func get_options() -> Dictionary:
	var stored = load_save().get("options", {})
	var out := DEFAULT_OPTIONS.duplicate()
	if stored is Dictionary:
		for key in out:
			if (stored as Dictionary).has(key):
				out[key] = (stored as Dictionary)[key]
	# Coerce: a hand-edited or older file must never poison the audio server.
	for key in ["master", "music", "sfx"]:
		out[key] = clampf(float(out[key]), 0.0, 1.0)
	for key in ["fullscreen", "reduced_motion", "reduced_flash", "music_on"]:
		out[key] = bool(out[key])
	return out

static func set_option(key: String, value: Variant) -> void:
	var d := load_save()
	var opts = d.get("options", {})
	if not (opts is Dictionary):
		opts = {}
	(opts as Dictionary)[key] = value
	d["options"] = opts
	save_save(d)

static func get_purchased_meta() -> Array:
	var d := load_save()
	var m = d.get("meta", [])
	if m is Array:
		return m
	return []

static func is_meta_purchased(id: String) -> bool:
	return get_purchased_meta().has(id)

static func purchase_meta(id: String) -> bool:
	if is_meta_purchased(id):
		return false
	# Find the upgrade def to get cost
	var def: Dictionary = {}
	for u in Content.META_UPGRADES:
		if u.id == id:
			def = u
			break
	if def.is_empty():
		return false
	var cost: int = int(def.cost)
	if not spend_cells(cost):
		return false
	var d := load_save()
	var arr: Array = d.get("meta", [])
	if not (arr is Array): arr = []
	arr.append(id)
	d["meta"] = arr
	save_save(d)
	return true

## Returns a build-dict delta from all purchased meta upgrades, applied at run start.
static func get_meta_modifiers() -> Dictionary:
	var out := {"max_hp": 0.0, "speed_mul": 0.0, "dmg_mul": 0.0, "flask": 0, "special_start": 0.0}
	var purchased: Array = get_purchased_meta()
	for id in purchased:
		for u in Content.META_UPGRADES:
			if u.id == id:
				match u.kind:
					"max_hp": out.max_hp += float(u.value)
					"speed_mul": out.speed_mul += float(u.value)
					"dmg_mul": out.dmg_mul += float(u.value)
					"flask": out.flask += int(u.value)
					"special_start": out.special_start = maxf(float(out.special_start), float(u.value))
				break
	return out
