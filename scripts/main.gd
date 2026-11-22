extends Node2D
## Game entry point: owns the simulation, camera, input and speed controls.

const Sim := preload("res://scripts/sim/sim.gd")
const Layout := preload("res://scripts/sim/layout.gd")
const WorldView := preload("res://scripts/view/world_view.gd")
const UI := preload("res://scripts/ui/ui.gd")

const SAVE_PATH := "user://savegame.txt"
const MIN_ZOOM := 0.6
const MAX_ZOOM := 4.0

var balance: Dictionary
var sim
var speed := 1
var _speed_before_pause := 1
var world
var camera := Camera2D.new()
var ui
var _drag_from := Vector2.INF
var _dragging := false


func _ready() -> void:
	balance = Sim.load_balance()
	world = WorldView.new()
	add_child(world)
	camera.zoom = Vector2(1.5, 1.5)
	camera.position = Vector2(190, 175)
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.new()
	ui.main = self
	layer.add_child(ui)
	_start_sim("campaign")
	ui.show_start(FileAccess.file_exists(SAVE_PATH))


func _start_sim(mode: String) -> void:
	sim = Sim.new()
	sim.new_game(balance, mode)
	_attach()


func _attach() -> void:
	world.setup(sim)
	ui.sim = sim
	ui.refresh()


func new_game(mode: String) -> void:
	_start_sim(mode)
	ui.close_modal()
	speed = 1
	ui.toast("Welcome! Check-out is 7-11 AM, check-in from 3 PM. Clean the rooms in between!")


func save_game() -> void:
	if sim.save_to(SAVE_PATH):
		ui.toast("Game saved.")
	else:
		ui.toast("Couldn't save the game.")


func load_game() -> void:
	var s = Sim.new()
	if s.load_from(balance, SAVE_PATH):
		sim = s
		_attach()
		ui.close_modal()
		ui.toast("Game loaded: day %d." % sim.day())
	else:
		ui.toast("No saved game found.")


func set_speed(s: int) -> void:
	if s == 0 and speed != 0:
		_speed_before_pause = speed
	speed = s


func _process(delta: float) -> void:
	if sim == null:
		return
	if speed > 0 and not ui.is_modal_open() and sim.game_over == "":
		sim.tick(delta * balance["minutes_per_second"] * speed)
	for e in sim.pop_events():
		ui.push_log(e)
		match e["type"]:
			"discount":
				ui.queue_discount(e["guest"])
			"day_end":
				ui.queue_report(e["report"])
			"game_over":
				ui.show_game_over(e["text"])
	ui.refresh()
	_keyboard_pan(delta)
	_update_hover()


# --------------------------------------------------------------------------- camera + input

func _keyboard_pan(delta: float) -> void:
	if ui.is_modal_open() and ui.modal_kind != "help":
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	camera.position += dir * 500.0 * delta / camera.zoom.x
	_clamp_camera()


func _clamp_camera() -> void:
	camera.position = camera.position.clamp(Vector2(-500, -150), Vector2(700, 500))


func _zoom(factor: float, at_screen := Vector2.INF) -> void:
	var before := get_global_mouse_position()
	var z := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	if at_screen != Vector2.INF:
		camera.force_update_scroll()
		camera.position += before - get_global_mouse_position()
	_clamp_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if ui.is_modal_open() and ui.modal_kind in ["rates", "staff", "reviews", "help"]:
					ui.close_modal()
			KEY_SPACE:
				set_speed(_speed_before_pause if speed == 0 else 0)
			KEY_1:
				set_speed(1)
			KEY_2:
				set_speed(2)
			KEY_3:
				set_speed(4)
			KEY_F:
				sim.order_desk()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_zoom(1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom(1.0 / 1.15)
	if ui.is_modal_open():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.0 / 1.1, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_drag_from = event.position
				_dragging = false
			else:
				if not _dragging and event.button_index == MOUSE_BUTTON_LEFT:
					_click(get_canvas_transform().affine_inverse() * event.position)
				_drag_from = Vector2.INF
				_dragging = false
	elif event is InputEventMouseMotion and _drag_from != Vector2.INF:
		if _dragging or event.position.distance_to(_drag_from) > 6.0:
			_dragging = true
			camera.position -= event.relative / camera.zoom.x
			_clamp_camera()
	elif event is InputEventMagnifyGesture:
		_zoom(event.factor, event.position)
	elif event is InputEventPanGesture:
		camera.position += event.delta * 8.0 / camera.zoom.x
		_clamp_camera()


func _target_at(world_pos: Vector2) -> Dictionary:
	var cell := Layout.to_grid(world_pos)
	var room := Layout.cell_to_room(cell)
	if room >= 0:
		return {"type": "room", "room": room}
	# Badges float above rooms: let clicks on them count too.
	for i in Layout.ROOM_COUNT:
		var badge := Layout.room_badge_pos(i)
		if Rect2(badge - Vector2(42, 10), Vector2(84, 20)).has_point(world_pos):
			return {"type": "room", "room": i}
	if Layout.LOBBY.has_point(cell) or Layout.line_cells().has(cell):
		return {"type": "desk"}
	for key in world.characters_at(world_pos):
		if key.begins_with("g"):
			return {"type": "desk"}
	return {}


func _click(world_pos: Vector2) -> void:
	var t := _target_at(world_pos)
	match t.get("type", ""):
		"room":
			if sim.order_clean(t["room"]):
				ui.toast("Added to your to-do list: clean room %d." % (t["room"] + 1))
		"desk":
			sim.order_desk()
			ui.toast("Heading to the front desk.")


func _update_hover() -> void:
	if ui.is_modal_open():
		world.overlay.hover_room = -1
		world.overlay.hover_desk = false
		ui.set_hint("")
		return
	var t := _target_at(get_global_mouse_position())
	world.overlay.hover_room = t["room"] if t.get("type", "") == "room" else -1
	world.overlay.hover_desk = t.get("type", "") == "desk"
	match t.get("type", ""):
		"room":
			var r = sim.rooms[t["room"]]
			var desc := "Room %d (%s)" % [r.index + 1, sim.bal["room_types"][r.type]["name"]]
			if r.state == "dirty":
				ui.set_hint(desc + " - dirty. Click to clean it.")
			elif r.state == "occupied":
				ui.set_hint(desc + " - a guest is staying here.")
			else:
				ui.set_hint(desc + " - clean and ready.")
		"desk":
			ui.set_hint("Front desk - click to work the desk. %d in line." % sim.queue.size())
		_:
			ui.set_hint("")
