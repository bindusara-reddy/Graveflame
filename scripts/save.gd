class_name Save
extends RefCounted
## Persistent save: cells (meta currency), best score, purchased meta upgrades.
## Stored as JSON at user://graveflame_save.json. Dead Cells-style meta progression.

const SAVE_PATH := "user://graveflame_save.json"

static func load_save() -> Dictionary:
	var defaults := {"cells": 0, "best_score": 0, "meta": []}
	if not FileAccess.file_exists(SAVE_PATH):
		return defaults
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
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
	return d

static func save_save(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Save: could not write to %s" % SAVE_PATH)
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
