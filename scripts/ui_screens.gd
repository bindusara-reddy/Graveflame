class_name UiScreens
extends Control
## Every full screen, and how the knight moves between them. Each page lives
## in its own script, cut from the kit (ui_screen.gd is their common base):
##   ui_title.gd    the landing: wordmark, quiet entries, the roll      "title"
##   ui_forms.gd    THE FORMS: every key and pad button, rebinding       "keys"
##   ui_pause.gd    THE KEEP WAITS and the ledger of this descent        "pause"
##   ui_senses.gd   SENSES: hearing, sight and hand                      "options"
##   ui_forge.gd    THE FORGE: relics and vows                           "forge"
##   ui_reward.gd   THE FLAME OFFERS: the boon deal                      "reward"
##   ui_results.gd  the grave and the crown: how a descent ended         "gameover", "victory"
## This stage owns what they share: showing and hiding, focus that follows the
## mouse, one way back out of every page, and arming buttons so nothing mashed
## through a transition can choose for the knight.

const Kit := preload("res://scripts/ui_kit.gd")
const T := preload("res://scripts/ui_theme.gd")
const TitlePage := preload("res://scripts/ui_title.gd")
const FormsPage := preload("res://scripts/ui_forms.gd")
const PausePage := preload("res://scripts/ui_pause.gd")
const SensesPage := preload("res://scripts/ui_senses.gd")
const ForgePage := preload("res://scripts/ui_forge.gd")
const RewardPage := preload("res://scripts/ui_reward.gd")
const ResultsPage := preload("res://scripts/ui_results.gd")

## Screens the title opens. Opened from the title they lie on its tableau,
## veiled, instead of replacing it.
const TITLE_SUBSCREENS := ["forge", "options", "keys"]
## Actions that must be let go before a result screen arms: jump and attack
## get mashed through the transition, and pad A is also ui_accept.
const ARM_RELEASE_ACTIONS := ["ui_accept", "jump", "attack", "interact"]

## The facade whose signals every page raises.
var ui: UI
var _panels: Dictionary = {}
var title: TitlePage
var forms: FormsPage
var pause: PausePage
var senses: SensesPage
var forge: ForgePage
var reward: RewardPage
var grave: ResultsPage
var crown: ResultsPage

## { panel, actions, modes } while a results panel waits for held keys to lift.
var _input_lock: Dictionary = {}
## Buttons waiting to arm: { buttons, at_ms, focus }, empty when none are.
var _arming: Dictionary = {}
## Frame of the knight's last navigation press or hover. Focus that moves in
## that frame was moved by hand and ticks; focus placed by code (a page
## opening, a list rebuilding) stays silent.
var _nav_frame := -1
var _last_panel := ""
## Whether the title is showing beneath a sub-screen.
var _title_under := false


## Build every page, hidden. `facade` is the UI whose signals they raise.
## Later pages draw over earlier ones.
func build(facade: UI) -> void:
	ui = facade
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = _page(TitlePage, "title")
	pause = _page(PausePage, "pause")
	reward = _page(RewardPage, "reward")
	grave = _page(ResultsPage, "gameover")
	crown = _page(ResultsPage, "victory")
	forge = _page(ForgePage, "forge")
	senses = _page(SensesPage, "options")
	forms = _page(FormsPage, "keys")


func _page(script: GDScript, panel_name: String) -> Control:
	var page: Control = script.new()
	add_child(page)
	page.mount(self, panel_name)
	page.visible = false
	_panels[panel_name] = page
	return page


# --- Panels ------------------------------------------------------------------------

func is_panel_visible(panel_name: String) -> bool:
	return _panels.has(panel_name) and (_panels[panel_name] as Control).visible


## Show a screen, fading it in over `fade` seconds. Returns false for an
## unknown name, so the facade leaves the HUD alone.
func show_panel(panel_name: String, fade: float = 0.0) -> bool:
	if not _panels.has(panel_name):
		return false
	var page: Control = _panels[panel_name]
	page.visible = true
	page.modulate = Color.WHITE
	# Settings screens settle onto the veil rather than cutting in.
	if panel_name in TITLE_SUBSCREENS:
		fade = maxf(fade, 0.2)
	if fade > 0.0 and not T.still():
		page.modulate.a = 0.0
		Kit.tween(self).tween_property(page, "modulate:a", 1.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var from := _last_panel
	_underlay_title(panel_name in TITLE_SUBSCREENS and (from == "title" or _title_under))
	_last_panel = panel_name
	if panel_name == "keys":
		forms.from_title = false
	page.opened(from)
	return true


## Keep the title's tableau up beneath a sub-screen with its menu hidden, so
## nothing under the veil can take focus; or give the title its menu back.
func _underlay_title(under: bool) -> void:
	_title_under = under
	title.holder.visible = not under
	if under:
		title.visible = true


func hide_panel(panel_name: String) -> void:
	if _panels.has(panel_name):
		(_panels[panel_name] as Control).visible = false
	if panel_name == "keys":
		forms.cancel_rebind()


func hide_all_panels() -> void:
	for page in _panels.values():
		(page as Control).visible = false
	forms.cancel_rebind()


# --- The title's Forms -------------------------------------------------------------

## THE FORMS from the landing: the Forms page laid over the tableau, closed
## again by its own way back, without the game ever leaving the title.
func toggle_title_controls() -> void:
	if forms.visible:
		forms.back()
		return
	forms.sync()
	show_panel("keys")
	forms.from_title = true


## Put the Forms away and hand focus back to the entry that opened them.
func close_forms_to_title() -> void:
	hide_panel("keys")
	show_panel("title")
	title.forms_entry.grab_focus.call_deferred()


# --- Navigation --------------------------------------------------------------------

## Runs before GUI navigation (the facade's _input), so a pending rebind hears
## the arrow keys and Enter first, and so a navigation press is known before
## focus moves.
func handle_input(event: InputEvent) -> void:
	if forms.listening():
		if forms.hear(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_focus_hovered()
		return
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(action, true):
			_nav_frame = Engine.get_process_frames()


## Hovering a button or slider focuses it, so the mouse and the pad never
## light two controls at once.
func _focus_hovered() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered.has_focus() or hovered.focus_mode == Control.FOCUS_NONE:
		return
	if not (hovered is BaseButton or hovered is Slider):
		return
	if hovered is BaseButton and (hovered as BaseButton).disabled:
		return
	_nav_frame = Engine.get_process_frames()
	hovered.grab_focus()


func on_focus_changed(_control: Control) -> void:
	if Engine.get_process_frames() == _nav_frame:
		ui.cue.emit("ui_move")


## Esc, pad B and pad START leave a settings page through its own way back,
## so every page exits one way and a paused descent behind it never sees the
## press. B on the pause sheet rises. Returns whether a page took it.
func _back_out(event: InputEvent) -> bool:
	for panel_name in ["keys", "options", "forge"]:
		if is_panel_visible(panel_name):
			((_panels[panel_name] as Control).get_meta("back_button") as Button).pressed.emit()
			return true
	if is_panel_visible("pause") and event.is_action_pressed("ui_cancel"):
		ui.resume_requested.emit()
		return true
	return false


func handle_unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _back_out(event):
			get_viewport().set_input_as_handled()
			return
	# Boon cards print their number, so the number keys have to take them.
	if event is InputEventKey and event.pressed and not event.echo and reward.visible:
		if reward.take_by_key((event as InputEventKey).keycode):
			get_viewport().set_input_as_handled()


## Per-frame upkeep, paused or not (driven by the facade's _process): lifts
## input locks, arms waiting buttons, and lets the title flicker.
func tick(delta: float) -> void:
	_poll_input_lock()
	_poll_arming()
	title.tick(delta)


# --- Arming ------------------------------------------------------------------------

## Hold `buttons` inert (unfocusable, unclickable) until `delay` real seconds
## have passed and no confirm-capable action is held, then focus `focus`. A
## jump or attack mashed through a transition can then never take a boon or
## start the descent again before the page has been read.
func arm_buttons(buttons: Array, delay: float, focus: Control) -> void:
	_restore_armed()
	for button: Control in buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arming = { "buttons": buttons, "at_ms": Time.get_ticks_msec() + roundi(delay * 1000.0), "focus": focus }


func awaiting_arm(button: Control) -> bool:
	return (_arming.get("buttons", []) as Array).has(button)


## Polled every frame: arms the waiting buttons once their delay has passed
## and every confirm-capable action has been let go.
func _poll_arming() -> void:
	if _arming.is_empty() or Time.get_ticks_msec() < int(_arming.at_ms):
		return
	for action in ARM_RELEASE_ACTIONS:
		if Input.is_action_pressed(action):
			return
	var focus: Control = _arming.focus
	_restore_armed()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()


## Give the waiting buttons back their focus and clicks, without focusing any.
func _restore_armed() -> void:
	for button in _arming.get("buttons", []):
		if is_instance_valid(button):
			(button as Control).focus_mode = Control.FOCUS_ALL
			(button as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	_arming = {}


## Keys still held from the ending (a gather, a skip) must not press a results
## button: the panel's buttons stay disabled until none of `actions` is held,
## then its first button takes focus. An empty panel name lifts any lock.
func lock_until_released(panel_name: String, actions: Array) -> void:
	_lift_input_lock()
	if not _panels.has(panel_name):
		return
	# Each button's own focus mode comes back with it: prompt links never
	# join the focus chain, locked or not.
	var modes := {}
	for button: Button in _panels[panel_name].find_children("*", "Button", true, false):
		modes[button] = button.focus_mode
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	_input_lock = { "panel": panel_name, "actions": actions, "modes": modes }


## Polled every frame, paused or not.
func _poll_input_lock() -> void:
	if _input_lock.is_empty():
		return
	for action in _input_lock.actions:
		if Input.is_action_pressed(action):
			return
	var page: Control = _panels[_input_lock.panel]
	_lift_input_lock()
	Kit.focus_first_control(page)


## Hand the locked panel's buttons back, whether the keys lifted or a new lock
## (or none) replaces this one.
func _lift_input_lock() -> void:
	if _input_lock.is_empty():
		return
	var modes: Dictionary = _input_lock.modes
	for button: Button in modes:
		if is_instance_valid(button):
			button.disabled = false
			button.focus_mode = modes[button]
	_input_lock = {}


# --- What the game tells the pages -------------------------------------------------

func set_victory_extras(ordinal: String, first: bool) -> void:
	crown.set_extras(ordinal, first)


func show_run_cells(cells_earned: int, panel_name: String, vows_kept: int = 0) -> void:
	(_panels[panel_name] as ResultsPage).show_cells(cells_earned, vows_kept)


func show_run_summary(stats: Dictionary, panel_name: String) -> void:
	(_panels[panel_name] as ResultsPage).show_summary(stats)


func set_descent(taken: Dictionary, seed_value: int, chamber: Dictionary = {}) -> void:
	pause.set_descent(taken, seed_value, chamber)


func setup_upgrades(upgrades: Array) -> void:
	reward.deal(upgrades)


func setup_forge(cells: int) -> void:
	forge.setup(cells)


func sync_options(opts: Dictionary) -> void:
	senses.sync(opts)


## Repaint the Forms from the live input map, ending any rebind in progress.
func sync_keys() -> void:
	forms.sync()


## Repaint the Forms' caps from the live input map (a rebind already landed).
func sync_controls() -> void:
	forms.repaint()


## The keep's tally of every descent, as the Forge reads it aloud: flames
## carried out (victories), knights fallen (with "more than" when deaths from
## before the count began are unknown) and, with `with_oath`, the hardest
## oath kept. Empty when there is nothing yet to tell.
static func roll_line(record: Dictionary, with_oath := true) -> String:
	var flames := int(record.get("victories", 0))
	var falls := int(record.get("falls", 0))
	var legacy := bool(record.get("falls_legacy", false))
	if flames == 0 and falls == 0 and not legacy:
		return ""
	var fallen := "%s %s fallen." % [_counted(falls), "knight" if falls == 1 else "knights"]
	if legacy:
		fallen = "More than %s knights fallen." % Content.number_word(falls)
	elif falls == 0:
		fallen = "No knight fallen."
	var carried := "%s %s carried out." % [_counted(flames), "flame" if flames == 1 else "flames"]
	if flames == 0:
		carried = "No flame carried out yet."
	var parts := [carried, fallen]
	if with_oath and bool(record.get("oath_kept", false)):
		parts.append("The fivefold oath is kept.")
	elif with_oath and flames > 0:
		parts.append("The highest oath: %s of %s." % [Content.number_word(int(record.get("best_vows", 0))), Content.number_word(Content.VOWS.size())])
	return "  ".join(parts)


## A count as the keep writes it at the start of a sentence: "Twelve", "47".
static func _counted(n: int) -> String:
	return Content.number_word(n).capitalize()


# --- Handles the contract suites reach through the facade --------------------------

var _reduced_motion_check: CheckBox:
	get: return senses.reduced_motion
var _option_sliders: Dictionary:
	get: return senses.sliders
var _option_checks: Dictionary:
	get: return senses.checks
var _quit_button: Button:
	get: return pause.quit_button
var _descent_grid: GridContainer:
	get: return pause.boons
var _descent_detail: Label:
	get: return pause.detail
var _descent_seed: Label:
	get: return pause.seed_label
var _upgrade_row: HBoxContainer:
	get: return reward.row
var _forge_rows: VBoxContainer:
	get: return forge.rows
var _key_rows: VBoxContainer:
	get: return forms.rows
var _listening_action: String:
	get: return forms.listening_action
var _title_top_label: Label:
	get: return title.face
var _title_tableau: Control:
	get: return title.tableau
var _title_holder: Control:
	get: return title.holder
## THE FORMS the title opens (the same page the Senses open).
var _title_controls: Control:
	get: return forms
