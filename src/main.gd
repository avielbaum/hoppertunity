## The game you see: draws the Sim, takes the mouse and keyboard, and shows the crew's conversations.
## Everything is built in code so the scene file stays one node. Rules live in sim.gd, words in crew.gd.
extends Node3D

const GATEWAY := "http://127.0.0.1:8080"  # the local Anansi gateway (see README); the game plays without it
const SAVE := "user://hoppertunity.json"
const SETTINGS := "user://hoppertunity_settings.json"
const TICK := 0.25
const MODELS := "res://assets/models/"
const PEOPLE := "res://assets/characters/"
## model, scale, tint and arrow height of each building. The kit's pieces run along +X, which is direction 0.
const LOOK := {
	"belt": ["conveyor-stripe", 1.0, Color.WHITE, 0.42], "splitter": ["conveyor-stripe", 1.0, Color(1.0, 0.75, 0.35), 0.42],
	"hopper": ["hopper-square", 0.85, Color.WHITE, 0.9],
	"inbound": ["structure-doorway-wide", 0.5, Color(0.75, 1.0, 0.8), 1.53], "outbound": ["structure-doorway-wide", 0.5, Color(1.0, 0.8, 0.6), 1.53],
	"press": ["machine", 0.75, Color.WHITE, 1.0], "molder": ["machine-window", 0.75, Color(0.75, 0.95, 1.0), 1.0],
	"assembler": ["machine-fortified", 0.72, Color(1.0, 0.9, 0.75), 1.0], "packer": ["robot-arm-a", 0.42, Color.WHITE, 0.03],
	"winder": ["machine", 0.75, Color(1.0, 0.72, 0.5), 1.0], "fitter": ["robot-arm-b", 0.42, Color(0.75, 1.0, 0.8), 0.03],
}
const ITEM_LOOK := {
	"steel": ["box-small", 0.55, Color(0.62, 0.66, 0.78)], "plastic": ["box-small", 0.55, Color(0.45, 0.9, 1.0)],
	"cardboard": ["box-wide", 0.5, Color.WHITE], "panel": ["cog-a", 0.5, Color(0.8, 0.84, 0.95)],
	"casing": ["cog-a", 0.5, Color(0.45, 0.9, 1.0)], "gadget": ["button-floor-round", 1.0, Color.WHITE],
	"boxed": ["box-large", 0.5, Color.WHITE],
	"copper": ["box-small", 0.55, Color(1.0, 0.6, 0.35)], "coil": ["cog-a", 0.5, Color(1.0, 0.6, 0.35)],
	"smart": ["button-floor-round", 1.0, Color(0.6, 1.0, 0.7)],
}
const CREW_LOOK := {"dock": "character-worker", "tech": "character-male-c", "qa": "character-female-e", "sales": "character-female-b"}
const HELP := "Every key has a button in the bottom bar, so a touch screen works too. Click a build button (or press its number), then the floor; click it again to put the tool away. Drag the floor to move the view. R turns the piece, right-click cancels or removes. Click a coworker to talk, a building to inspect it, an inbound dock to change what it orders. WASD or arrows move, Q and E turn the view, the wheel zooms, Space pauses, M mutes everything, N just the music, F3 shows the frame rate."
## The tutorial. A new game opens on a small working line (Sim.starter), and Pip is walked through building a second
## one beside it, one piece at a time. Each step: what she is told, the build button that pulses, and the floor tile that
## glows (or null). _tutorial_done() says when a step is finished.
const TUTORIAL := [
	["[font_size=28][b]Hoppertunity[/b][/font_size]\nYou are Pip Hopper, the new floor manager of the Hopper Works. Ship five contracts and the plant is saved. Look after the four people who run it, or it will not be.\n\nThis is your line. Steel comes in at the [b]green dock[/b], the [b]press[/b] stamps it into panels, and the [b]orange dock[/b] ships them. Watch a couple of crates make the trip.", "", null],
	["Every panel sold is money. But the contract up top wants 20 by the end of day 2, and one press is slow. Let's build a second line.\n\nClick [b]Inbound dock[/b] below, then the glowing tile.", "inbound", Vector2i(4, 7)],
	["The orange arrow on a building shows which way it sends things.\n\nNow a [b]Press[/b] on the next glowing tile, right where the dock's arrow points.", "press", Vector2i(5, 7)],
	["A [b]Conveyor[/b] carries things one tile along its arrow. Put one after the press.", "belt", Vector2i(6, 7)],
	["And an [b]Outbound dock[/b] at the end to sell what arrives.", "outbound", Vector2i(7, 7)],
	["Two lines running! Time is yours to bend: the [b]> >> >>>[/b] buttons at the top speed it up, [b]||[/b] or Space pauses. Try one.", "", null],
	["Four people keep this plant going, and their mood sets how fast their part of it runs. Click one of them (their names float over their heads).", "", null],
	["Type anything and press Enter: kindness lifts morale, rudeness sinks it. Or click [b]Any work?[/b] for an errand that pays.", "", null],
	["Do the errand: the orange line up top says how, and what it wants is marked in orange on the floor. Everyone loses a little morale each day, so keep talking, helping and paying fairly.\n\nThat is the job. Good luck, Pip!", "", null],
]
const TRUCK_LOAD := 12  # crates a truck brings or takes before it drives off and the next one backs in
const PERSONAL := 0.55  # how close two people may stand, in tiles
const INK := Color("2b2a3a")
const ORANGE := Color("f2a13c")

var sim: Sim
var crew: Crew
var player_id := ""
var speed := 1.0
var acc := 0.0
var tool := ""  # the building being placed, "remove" for the remove tool, "" for none
var tool_dir := 0
var last_clicked := Vector2i(-1, -1)  # the tile last clicked with no tool, for the Turn button
var remove_button: Button
var talking := ""  # the coworker in the talk panel
var modal := false  # a question or report is up (see _ask): time stands still
var modal_queue := []  # the ones waiting their turn
var modal_now := {}  # the one on screen
var asked_offers := false
var told_bankrupt := false
var show_fps := false
var save_path := SAVE  # the checks point this at a file of their own before the game starts
var stress := false  # the developer's full-floor test (see _stress)
var music_vol := 0.5  # 0 to 1, set in the ? screen and kept in SETTINGS
var sfx_vol := 0.8
var speed_buttons := {}  # speed -> its button
var tutorial := 0  # the step Pip is on; past the end means finished or skipped

var cam := Camera3D.new()
var pivot := Vector3(6, 0, 4)
var yaw := 0
var zoom := 22.0
var views := {}  # Vector2i -> the building's Node3D (conveyors have none: they are drawn in batches, see _draw_belts)
var belt_mm := {}  # "belt", "corner", "splitter", "arrow" -> MultiMesh
var belts_dirty := true
var trucks := {}  # Vector2i of a dock -> {"node", "home", "front", "count", "last_t", "away"}: the van parked at it
var item_mm := {}  # item id -> MultiMesh
var floor_mm := MultiMesh.new()
var scenery := Node3D.new()  # the building around the floor: apron, walls on the far sides, props (see _scenery)
var scenery_for := []  # the floor size and view it was built for
const APRON := 2  # tiles of walkway between the build floor and the walls
const TOWN := ["commercial/building-a.glb", "commercial/building-c.glb", "commercial/building-e.glb", "commercial/building-g.glb",
		"commercial/building-j.glb", "commercial/building-k.glb", "industrial/building-e.glb", "industrial/building-j.glb"]
var ghost := Node3D.new()
var ghost_key := ""
var crew_nodes := {}  # crew id (and "pip") -> Node3D
var routes := {}  # crew id or "pip" -> the points they still have to walk through
var crew_home := {}  # crew id -> their spot by the back wall
var crew_stop := {}  # crew id -> which stop of their beat they are on
var crew_wait := {}  # crew id -> seconds until they move on

var top: Label
var contract_label: Label
var quest_label: Label
var day_bar: ProgressBar
var build_bar: HFlowContainer  # wraps onto a second row when everything is unlocked
var toast: Label
var talk_panel: PanelContainer
var talk_log: RichTextLabel
var talk_title: Label
var talk_face: TextureRect
var talk_input: LineEdit
var raise_row: HBoxContainer
var modal_panel: PanelContainer
var modal_text: RichTextLabel
var modal_buttons: VBoxContainer
var chart := Control.new()  # the day-end screen's picture of the last two weeks
var sound_box := VBoxContainer.new()  # the ? screen's volume sliders
var net_label: Label
var tut_panel: PanelContainer
var sideways: Label  # shown over everything on a screen taller than it is wide
var bottom_panel: PanelContainer  # the build bar's panel
var bar_toggle: Button  # on a small screen the build bar is closed until this opens it
var bar_open := false
var new_game_button: Button
var bar_tool := ""  # the tool in hand when the bar was last looked at, to close the bar when one is picked
var mini: PanelContainer  # on a small screen, with the bar closed and a tool in hand: Turn and Put away
var tag_canvas := Control.new()  # building tags are painted here, under the panels
var tags_seen := []
var saved_at := 0  # sim.ticks at the last save
var tut_text: RichTextLabel
var tut_marker := MeshInstance3D.new()  # the glowing tile the tutorial wants built on
var build_buttons := {}  # kind -> its button in the build bar
var sounds := {}  # sound name -> its AudioStreamPlayer
var music := AudioStreamPlayer.new()
var last_sell := 0  # when the sale sound last played, so a busy dock does not machine-gun it


func _ready() -> void:
	for f in ["click", "place", "remove", "sell", "error", "talk", "win", "step", "day", "up", "down"]:
		var a := AudioStreamPlayer.new()
		a.stream = load("res://assets/audio/%s.ogg" % f)
		add_child(a)
		sounds[f] = a
	if FileAccess.file_exists(SETTINGS):
		var set = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if set is Dictionary:
			music_vol = clampf(float(set.get("music", music_vol)), 0.0, 1.0)
			sfx_vol = clampf(float(set.get("sfx", sfx_vol)), 0.0, 1.0)
	music.stream = load("res://assets/audio/music.mp3")
	music.stream.loop = true
	_volumes()
	add_child(music)
	music.play()
	_world()
	_ui()
	stress = "stress" in OS.get_cmdline_user_args() or (OS.has_feature("web") and "stress" in str(JavaScriptBridge.eval("location.search")))
	var saved := {} if stress else _load()
	_start(saved)
	if OS.has_feature("web") and "remark" in str(JavaScriptBridge.eval("location.search")):
		_time_remark()
	if stress:
		_stress()
	elif not saved.is_empty():  # a new game needs no title card: its tutorial's first step is the introduction
		_ask("[font_size=30][b]Hoppertunity[/b][/font_size]\n\nThe Hopper Works is as you left it, on day %d with %d coins." % [sim.day, sim.money],
				[["Back to work", Callable()], ["New game", _new_game]])


## Developer aid (`?remark` in the browser): ask the gateway for a streamed day-end remark straight away and print to
## the browser console when each sentence arrives, to see whether a browser really gets them one at a time.
func _time_remark() -> void:
	crew.online = true
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await crew.remark("tech", "We shipped 31 units, 4 came back defective, and the plant made 120 coins of profit.",
			func(part): print("REMARK +%.1f s: %s" % [(Time.get_ticks_msec() - t0) / 1000.0, part]))
	print("REMARK done, %s, %.1f s" % [r.source, (Time.get_ticks_msec() - t0) / 1000.0])


## Developer aid (`?stress` in the browser, `-- stress` on the desktop): the largest floor, every tile a moving conveyor,
## to see what the frame rate does. F3 shows it. Nothing is saved over a real game until a day ends.
func _stress() -> void:
	sim.money = 1000000
	sim.floor_size = Vector2i(28, 24)
	tutorial = TUTORIAL.size()
	show_fps = true
	var rows := 24
	var fill := "belt"
	if OS.has_feature("web"):  # ?stress=6 fills only six rows; &fill=hopper fills them with hoppers
		rows = clampi(int(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('stress') || 24"))), 1, 24)
		fill = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('fill') || 'belt'"))
	sim.unlocked = Data.BUILD.keys() + Data.ITEMS.keys()
	for y in rows:
		for x in 28:
			var east := y % 2 == 0
			var kind := "inbound" if x + y == 0 else ("outbound" if Vector2i(x, y) == Vector2i(0, 23) else fill)
			sim.build(kind, Vector2i(x, y), 1 if x == (27 if east else 0) else (0 if east else 2))
	_floor()
	for pos in sim.cells:
		_refresh(pos)
	pivot = Vector3(14, 0, 12)
	zoom = 34.0
	speed = 4.0
	while true:  # test/web.mjs reads this from the browser console
		await get_tree().create_timer(1.0).timeout
		print("STRESS %d fps, %d buildings, %d crates moving" % [Engine.get_frames_per_second(), sim.cells.size(),
				sim.cells.values().filter(func(c): return c.get("item", "") != "").size()])


# ---------- a game begins ----------

func _start(saved: Dictionary) -> void:
	sim = Sim.new(randi())
	if crew != null:
		crew.queue_free()
	crew = Crew.new()
	if saved.is_empty():
		player_id = "pip-%08x" % (randi() & 0x7fffffff)
		tutorial = 0
		sim.starter()
	else:
		tutorial = int(saved.get("tutorial", TUTORIAL.size()))
		sim.restore(saved.sim)
		crew.stories = saved.stories
		crew.told = saved.get("told", {})
		player_id = saved.player
	add_child(crew)
	crew.setup(sim, GATEWAY, "hoppertunity", "change-me", player_id)
	sim.sold.connect(_on_sold)
	sim.day_ended.connect(_on_day_end)
	sim.contract_changed.connect(_on_contract)
	sim.quest_changed.connect(_on_quest)
	for v in views.values():
		v.queue_free()
	views = {}
	trucks = {}
	belts_dirty = true  # or the last game's conveyors stay on screen
	for pos in sim.cells:
		_refresh(pos)
	_floor()
	_place_crew()
	_build_buttons()
	_close_talk()
	modal_queue.clear()
	modal_panel.hide()
	modal = false
	asked_offers = false
	told_bankrupt = false
	saved_at = sim.ticks
	acc = 0.0
	if sim.cells.size() >= 4:  # a new game waits for a first line to stand, so quests are about what is there
		crew.refill()


func _on_contract(done: bool) -> void:
	if done:
		_toast("Contract shipped! Check the build bar for anything new.")
		_sfx("win")
		_build_buttons()
		if sim.contracts_done == Data.WIN_CONTRACTS:
			_ask(("[font_size=24][b]Hoppertunity seized![/b][/font_size]\n\nFive contracts shipped by day %d. The bank has gone back to "
					+ "being polite, and the Hopper Works stays open.\n\nCash: %d coins. Crew morale: %d.") % [sim.day, sim.money, int(sim.team_morale())],
					[["Keep the plant running", Callable()], ["New game", _new_game]])


## Put a report or a question in front of the player. Time stops until it is answered. buttons: [label, Callable] pairs
## (an empty Callable just closes it). If one is already up, this one waits its turn.
func _ask(text: String, buttons: Array, extra := "") -> void:
	modal_queue.append({"text": text, "buttons": buttons, "extra": extra})
	if not modal:
		_next_modal()


func _next_modal() -> void:
	modal = not modal_queue.is_empty()
	modal_panel.visible = modal
	if not modal:
		return
	var m: Dictionary = modal_queue.pop_front()
	modal_now = m
	modal_text.text = m.text
	chart.visible = m.extra == "chart"
	sound_box.visible = m.extra == "sound"
	chart.queue_redraw()
	for ch in modal_buttons.get_children():
		ch.queue_free()
	for b in m.buttons:
		_button(b[0], modal_buttons, _answer.bind(b[1]))


func _set_volume(value: float, which: String) -> void:
	set(which, value)
	_volumes()
	if which == "sfx_vol":
		_sfx("click")


## A modal's button was pressed: close it (or show the next one), then do what the button stands for.
func _answer(act: Callable) -> void:
	_next_modal()
	if act.is_valid():
		act.call()


## Net result per day as bars (up is profit) and crew morale as a line, for the last 14 days.
func _paint_chart() -> void:
	var days: Array = sim.history.slice(-14)
	var w := chart.size.x / 14.0
	var mid := chart.size.y / 2.0
	var top_net := 1.0
	for d in days:
		top_net = maxf(top_net, absf(d.net))
	chart.draw_line(Vector2(0, mid), Vector2(chart.size.x, mid), Color("6b6890"))
	var line := PackedVector2Array()
	for i in days.size():
		var h: float = days[i].net / top_net * (mid - 4.0)
		chart.draw_rect(Rect2(i * w + 3, mid - maxf(h, 0.0), w - 6, absf(h)), Color("7fd68a") if h >= 0 else Color.TOMATO)
		line.append(Vector2(i * w + w / 2, chart.size.y - 2.0 - days[i].morale / 100.0 * (chart.size.y - 4.0)))
		chart.draw_string(ThemeDB.fallback_font, Vector2(i * w + 4, chart.size.y - 2), str(days[i].day), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9c99c4"))
	if line.size() > 1:
		chart.draw_polyline(line, ORANGE, 2.0)
	chart.draw_string(ThemeDB.fallback_font, Vector2(4, 11), "bars: profit per day   line: crew morale", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9c99c4"))


func _on_quest(done: bool) -> void:
	if done:
		var r: Dictionary = sim.last_reward
		var who: String = Data.CREW[r.giver].name
		_toast("Errand done: %d coins, and %s is happier.%s" % [r.cash, who,
				" %s is fired up: their work runs a fifth faster until the end of %s." % [who, "tomorrow" if r.boost == 1 else "the day after tomorrow"]
				if r.boost > 0 else ""])
		_play(crew_nodes[r.giver], "emote-yes", true)
		_sfx("win")


func _new_game() -> void:
	DirAccess.remove_absolute(save_path)
	_start({})


func _confirm_new_game() -> void:
	_ask("Start over? The saved game will be erased.", [["Yes, start over", _new_game], ["No, keep playing", Callable()]])


func _expand() -> void:
	if sim.expand():
		_floor()
		_build_buttons()
	else:
		_toast("Not enough money to expand.")


func _load() -> Dictionary:
	if FileAccess.file_exists(save_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if d is Dictionary and d.has("sim") and d.has("stories") and d.has("player"):
			return d
	return {}


func _save() -> void:
	if stress:  # a floor full of test conveyors must not replace a real game
		return
	saved_at = sim.ticks
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"sim": sim.save(), "stories": crew.stories, "told": crew.told, "player": player_id, "tutorial": tutorial}))


# ---------- the 3D world ----------

func _world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("23222d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9b6e0")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color("fff1dc")  # late-afternoon light through the factory's open sides
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	# one shadow map, not the default four: the camera is orthographic and sees one patch of floor, and four passes
	# cost a third of the frame rate on integrated graphics
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	add_child(scenery)
	tut_marker.mesh = PlaneMesh.new()
	tut_marker.mesh.size = Vector2(1, 1)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(ORANGE, 0.7)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tut_marker.mesh.material = glow_mat
	add_child(tut_marker)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 200.0
	add_child(cam)
	var fm := MultiMeshInstance3D.new()
	floor_mm.transform_format = MultiMesh.TRANSFORM_3D
	floor_mm.mesh = _mesh(MODELS + "floor.glb")
	fm.multimesh = floor_mm
	var fmat: BaseMaterial3D = floor_mm.mesh.surface_get_material(0).duplicate()
	fmat.albedo_color = Color(0.5, 0.5, 0.62)  # darker than the kit's floor, so machines and crates stand out
	fm.material_override = fmat
	add_child(fm)
	for id in ITEM_LOOK:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(MODELS + ITEM_LOOK[id][0] + ".glb")
		mm.instance_count = 1024  # shortcut: at most 1024 of one item are drawn, raise it if a floor ever holds more
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var mat: BaseMaterial3D = mm.mesh.surface_get_material(0).duplicate()
		mat.albedo_color = ITEM_LOOK[id][2]
		mi.material_override = mat
		add_child(mi)
		item_mm[id] = mm
	for key in ["belt", "corner", "splitter", "arrow"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _arrow_mesh() if key == "arrow" else _mesh(MODELS + ("conveyor-stripe-corner" if key == "corner" else "conveyor-stripe") + ".glb")
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if key == "splitter":
			var mat: BaseMaterial3D = mm.mesh.surface_get_material(0).duplicate()
			mat.albedo_color = LOOK.splitter[2]
			mi.material_override = mat
		add_child(mi)
		belt_mm[key] = mm
	add_child(ghost)


func _sfx(sound: String, db := 0.0) -> void:
	sounds[sound].volume_db = db + linear_to_db(maxf(sfx_vol, 0.001)) + 2.0
	if sfx_vol > 0.0:
		sounds[sound].play()


## Apply the two volume sliders (the music sits well under the effects) and remember them.
func _volumes() -> void:
	music.volume_db = linear_to_db(maxf(music_vol, 0.001)) - 14.0
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"music": music_vol, "sfx": sfx_vol}))


## A small flat orange arrowhead pointing along +X: every building wears one to show which way it sends things.
static func _arrow_mesh() -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3(0.3, 0.26, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ORANGE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	return m


## Where an arrow sits: the prism's tip (+Y) turned to the building's direction, lying flat at the given height.
static func _arrow_at(at: Vector3, dir: int) -> Transform3D:
	var ahead := Vector3(Data.DIRS[dir].x, 0, Data.DIRS[dir].y)
	return Transform3D(Basis(ahead.cross(Vector3.UP), ahead, Vector3.UP), at)


static func _mesh(path: String) -> Mesh:
	var n: Node = load(path).instantiate()
	var m: Mesh = n.find_children("*", "MeshInstance3D", true, false)[0].mesh
	n.free()
	return m


## Recolour every surface of a model (and optionally swap its palette texture) without touching the shared material.
static func _tint(n: Node, c: Color, tex: Texture2D = null) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat: BaseMaterial3D = mi.mesh.surface_get_material(i).duplicate()
			mat.albedo_color = c
			if tex != null:
				mat.albedo_texture = tex
			mi.set_surface_override_material(i, mat)


static func _center(pos: Vector2i) -> Vector3:
	return Vector3(pos.x + 0.5, 0.0, pos.y + 0.5)


## A building's model. turn >= 0 gives the conveyor corner piece,
## turned that many quarter turns (only the build preview needs that: placed conveyors are drawn in batches).
func _model(kind: String, dir: int, turn := -1) -> Node3D:
	var look: Array = LOOK[kind]
	var n := Node3D.new()
	var m: Node3D = load(MODELS + (look[0] if turn < 0 else "conveyor-stripe-corner") + ".glb").instantiate()
	m.scale = Vector3.ONE * look[1]
	m.rotation.y = -(dir if turn < 0 else turn) * PI / 2
	if look[2] != Color.WHITE:
		_tint(m, look[2])
	n.add_child(m)
	return n


## Where the arrow of a building of this kind goes, given the building's centre.
static func _arrow_spot(kind: String, center: Vector3, dir: int) -> Vector3:
	var ahead := Vector3(Data.DIRS[dir].x, 0, Data.DIRS[dir].y)
	return center + Vector3(0, LOOK[kind][3] + 0.02, 0) + (Vector3.ZERO if kind in ["belt", "splitter"] else ahead * 0.3)


## Conveyors, splitters and every building's arrow are drawn as four batches, however many there are: a floor full of
## conveyors as separate nodes drew nothing at all in the browser.
func _draw_belts() -> void:
	belts_dirty = false
	var lists := {"belt": [], "corner": [], "splitter": [], "arrow": []}
	for pos in sim.cells:
		var c: Dictionary = sim.cells[pos]
		lists.arrow.append(_arrow_at(_arrow_spot(c.kind, _center(pos), c.dir), c.dir))
		if c.kind in ["belt", "splitter"]:
			var turn := _corner(pos)
			var key: String = "corner" if turn >= 0 else c.kind
			lists[key].append(Transform3D(Basis(Vector3.UP, -(c.dir if turn < 0 else turn) * PI / 2), _center(pos)))
	for key in lists:
		belt_mm[key].instance_count = lists[key].size()
		for i in lists[key].size():
			belt_mm[key].set_instance_transform(i, lists[key][i])


## Would the building at `from` hand things to its neighbour `to`?
func _feeds(from: Vector2i, to: Vector2i) -> bool:
	var c = sim.cells.get(from)
	if c == null or c.kind == "outbound":
		return false
	var ahead: bool = from + Data.DIRS[c.dir] == to
	return ahead or (c.kind == "splitter" and from - Data.DIRS[c.dir] != to)


## Which way the corner piece must be turned for the conveyor at pos, or -1 if it should be straight: a corner only when
## nothing feeds it from behind and exactly one side does. At zero turns the piece joins the west and south edges.
func _corner(pos: Vector2i) -> int:
	var c: Dictionary = sim.cells[pos]
	if c.kind != "belt" or _feeds(pos - Data.DIRS[c.dir], pos):
		return -1
	var right := _feeds(pos + Data.DIRS[(c.dir + 1) % 4], pos)
	var left := _feeds(pos + Data.DIRS[(c.dir + 3) % 4], pos)
	return -1 if right == left else (c.dir + (3 if right else 2)) % 4


## Redraw the building at pos after it was built, turned or removed.
func _refresh(pos: Vector2i) -> void:
	belts_dirty = true
	trucks.erase(pos)
	if views.has(pos):
		views[pos].queue_free()
		views.erase(pos)
	if not sim.cells.has(pos) or sim.cells[pos].kind in ["belt", "splitter"]:
		return
	var c: Dictionary = sim.cells[pos]
	var n := _model(c.kind, c.dir)
	n.position = _center(pos)
	add_child(n)
	views[pos] = n
	if c.kind in ["inbound", "outbound"]:  # a van backed up to the dock, outside the line: behind an inbound dock, beyond an outbound one
		var ahead := Vector3(Data.DIRS[c.dir].x, 0, Data.DIRS[c.dir].y)
		var front := ahead if c.kind == "outbound" else -ahead
		var van: Node3D = load("res://assets/vehicles/delivery.glb").instantiate()
		van.scale = Vector3.ONE * 0.5
		van.rotation.y = atan2(front.x, front.z)  # the kit's vehicles face +Z
		van.position = front * 1.45
		n.add_child(van)
		trucks[pos] = {"node": van, "home": van.position, "front": front, "count": 0, "last_t": 0.0, "away": false}


## The factory building, for show: a walkway apron with hazard stripes round the build floor, the yard outside, walls
## with windows on the two sides away from the camera (so they never hide the floor), and a few props. Rebuilt when the
## floor grows or the view turns.
func _scenery() -> void:
	if scenery_for == [sim.floor_size, yaw]:
		return
	scenery_for = [sim.floor_size, yaw]
	for ch in scenery.get_children():
		ch.queue_free()
	var size := Vector2(sim.floor_size)
	var yard := MeshInstance3D.new()
	yard.mesh = PlaneMesh.new()
	yard.mesh.size = Vector2(160, 160)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("2a2933")
	yard.mesh.material = asphalt
	yard.position = Vector3(size.x / 2, -0.03, size.y / 2)
	scenery.add_child(yard)
	var apron := MultiMesh.new()
	var stripes := MultiMesh.new()
	var apron_at := []
	var stripes_at := []
	for x in range(-APRON, sim.floor_size.x + APRON):
		for y in range(-APRON, sim.floor_size.y + APRON):
			if x < 0 or y < 0 or x >= sim.floor_size.x or y >= sim.floor_size.y:
				apron_at.append(Transform3D(Basis(), _center(Vector2i(x, y)) + Vector3(0, -0.01, 0)))
				if x == -1 or y == -1 or x == sim.floor_size.x or y == sim.floor_size.y:  # the ring that touches the floor
					stripes_at.append(Transform3D(Basis(Vector3.UP, PI / 2 if (x == -1 or x == sim.floor_size.x) else 0.0), _center(Vector2i(x, y))))
	for pair in [[apron, apron_at, "floor", Color(0.3, 0.3, 0.4)], [stripes, stripes_at, "indicator-special-lines", Color(0.62, 0.5, 0.3)]]:
		pair[0].transform_format = MultiMesh.TRANSFORM_3D
		pair[0].mesh = _mesh(MODELS + pair[2] + ".glb")
		pair[0].instance_count = pair[1].size()
		for i in pair[1].size():
			pair[0].set_instance_transform(i, pair[1][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = pair[0]
		var mat: BaseMaterial3D = pair[0].mesh.surface_get_material(0).duplicate()
		mat.albedo_color = pair[3]
		mi.material_override = mat
		scenery.add_child(mi)
	# walls stand on the sides away from the camera
	var toward := Basis(Vector3.UP, yaw * PI / 2 + PI / 4).z  # from the floor toward the camera
	var wall_z := -APRON - 1.5 if toward.z > 0 else size.y + APRON + 1.5
	var wall_x := -APRON - 1.5 if toward.x > 0 else size.x + APRON + 1.5
	var x := -APRON - 1
	while x < sim.floor_size.x + APRON + 1:  # the wall that runs along X: pillars, with a wide window every few
		var wide := (x + APRON) % 5 == 2
		_prop("structure-window-wide" if wide else "structure-wall", Vector3(x + (1.0 if wide else 0.5), 0, wall_z), 0.0 if toward.z > 0 else PI)
		x += 2 if wide else 1
	var z := -APRON - 1
	while z < sim.floor_size.y + APRON + 1:  # and the one along Z
		var wide := (z + APRON) % 5 == 2
		_prop("structure-window-wide" if wide else "structure-wall", Vector3(wall_x, 0, z + (1.0 if wide else 0.5)), PI / 2 if toward.x > 0 else -PI / 2)
		z += 2 if wide else 1
	for corner in [Vector2(-1.5, -1.5), Vector2(size.x + 0.5, -1.5), Vector2(-1.5, size.y + 0.5), Vector2(size.x + 0.5, size.y + 0.5)]:
		_prop("cone", Vector3(corner.x + 0.5, 0, corner.y + 0.5), 0.0, 0.8)
	var far := Vector3(-1.4 if toward.x > 0 else size.x + 1.4, 0, -1.4 if toward.z > 0 else size.y + 1.4)
	_prop("crane", far, atan2(toward.x, toward.z) + PI, 0.6)
	# the town the Works stands in, behind those two walls: a road, then two rows of buildings on grass. It is on the
	# far sides only, like the walls, so nothing ever stands between the camera and the floor.
	var out_z := -1.0 if toward.z > 0 else 1.0  # which way "behind the wall" is, along each axis
	var out_x := -1.0 if toward.x > 0 else 1.0
	var mid := Vector3(size.x / 2, 0, size.y / 2)
	for side in 2:  # 0: the wall that runs along X; 1: the one along Z
		var along := Vector3.RIGHT if side == 0 else Vector3.BACK
		var out := Vector3(0, 0, out_z) if side == 0 else Vector3(out_x, 0, 0)
		var wall: Vector3 = mid + out * ((size.y if side == 0 else size.x) / 2 + APRON + 1.5)
		var length := 140.0
		for way in [1.0, -1.0]:  # the road and the grass run round all four sides; only the far two get buildings
			var edge: Vector3 = mid + out * way * ((size.y if side == 0 else size.x) / 2 + APRON + 1.5)
			_slab(edge + out * way * 4.5, along, length, 4.0, Color("1c1b22"), -0.02)   # the road
			_slab(edge + out * way * 4.5, along, length, 0.15, Color("8a8794"), -0.015)  # its centre line
			_slab(edge + out * way * 36.5, along, length, 60.0, Color("3d5244"), -0.025)  # grass
		for i in range(-8, 9):
			for row in 2:
				var pick: int = absi(i * 7 + row * 3 + side * 5) % TOWN.size()
				var at: Vector3 = wall + out * (9.5 + row * 5.5) + along * (i * 5.0 + row * 2.5)
				_prop_at("res://assets/town/" + TOWN[pick], at, (absi(i + row) % 4) * PI / 2, 3.4 + 0.5 * (absi(i * 3 + row) % 3))
	var corner := mid + Vector3(out_x * (size.x / 2 + APRON + 1.5), 0, out_z * (size.y / 2 + APRON + 1.5))  # where the two walls meet
	_prop_at("res://assets/town/industrial/water-tower.glb", corner + Vector3(out_x, 0, out_z) * 1.3, 0.0, 2.4)
	for k in 3:  # shipping containers in the yard outside the wall
		_prop_at("res://assets/town/industrial/shipping-container-a.glb", corner + Vector3(-out_x * (6.0 + k * 1.2), 0, out_z * 1.6), 0.0, 0.6)


## A flat strip of one colour on the ground, `length` long in the direction `along` and `width` wide, centred on `at`.
func _slab(at: Vector3, along: Vector3, length: float, width: float, colour: Color, height: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = PlaneMesh.new()
	m.mesh.size = Vector2(length, width) if along.x != 0 else Vector2(width, length)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.mesh.material = mat
	m.position = at + Vector3(0, height, 0)
	scenery.add_child(m)


func _prop_at(path: String, at: Vector3, turn: float, scale := 1.0) -> void:
	var n: Node3D = load(path).instantiate()
	n.position = at
	n.rotation.y = turn
	n.scale = Vector3.ONE * scale
	scenery.add_child(n)


func _prop(model: String, at: Vector3, turn: float, scale := 1.0) -> void:
	var n: Node3D = load(MODELS + model + ".glb").instantiate()
	n.position = at
	n.rotation.y = turn
	n.scale = Vector3.ONE * scale
	scenery.add_child(n)


func _floor() -> void:
	floor_mm.instance_count = sim.floor_size.x * sim.floor_size.y
	for x in sim.floor_size.x:
		for y in sim.floor_size.y:
			floor_mm.set_instance_transform(x * sim.floor_size.y + y, Transform3D(Basis().scaled(Vector3.ONE * 0.96), _center(Vector2i(x, y))))


## The crew stand in a row along the back edge of the floor, Pip at the end.
func _place_crew() -> void:
	for n in crew_nodes.values():
		n.queue_free()
	crew_nodes = {}
	var ids: Array = Data.CREW.keys() + ["pip"]
	for i in ids.size():
		var id: String = ids[i]
		var n: Node3D = load(PEOPLE + (CREW_LOOK[id] if id != "pip" else "character-female-d") + ".glb").instantiate()
		n.scale = Vector3.ONE * 1.6
		n.position = Vector3(2.0 + i * 1.6, 0, -1.0)
		if id == "pip":
			_tint(n, Color.WHITE, load(PEOPLE + "colormap-blonde.png"))
		var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
		ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
		ap.seek(i * 0.4)
		add_child(n)
		crew_nodes[id] = n
		crew_home[id] = n.position
		routes[id] = []
		crew_stop[id] = 0
		crew_wait[id] = 4.0 + i * 3.0


func _process(delta: float) -> void:
	if not modal and not sim.bankrupt():
		acc += delta * speed
		while acc >= TICK:
			acc -= TICK
			sim.step()
			if modal:
				acc = 0.0
				break
	_walk_crew(delta)
	_camera(delta)
	_scenery()
	if belts_dirty:
		_draw_belts()
	for pos in trucks:  # an inbound dock's counter drops back to zero each time it unloads a crate
		var c: Dictionary = sim.cells[pos]
		if c.kind == "inbound":
			if c.t < trucks[pos].last_t:
				_truck_load(pos)
			trucks[pos].last_t = c.t
	_draw_items(acc / TICK)
	_draw_tags()
	_draw_ghost()
	_hud()
	if sim.ticks - saved_at >= 80 and not sim.bankrupt():  # every 20 seconds of play, so closing the tab loses little
		_save()


## Send someone to a spot, around the buildings: Godot's grid pathfinder over the floor and a strip around it. If the
## spot is inside a building they stop as near as they can get; with no way through at all they walk straight there.
func _send(id: String, to: Vector3) -> void:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i(-2, -2), sim.floor_size + Vector2i(4, 4))
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for pos in sim.cells:
		grid.set_point_solid(pos)
	var from: Vector3 = crew_nodes[id].position
	var a := Vector2i(floori(from.x), floori(from.z))
	var b := Vector2i(floori(to.x), floori(to.z))
	var route := []
	if grid.is_in_boundsv(a) and grid.is_in_boundsv(b):
		grid.set_point_solid(a, false)  # something was built where they stand: let them walk out of it
		for cell in grid.get_id_path(a, b, true).slice(1):
			route.append(_center(cell))
	if route.is_empty():
		route = [to]
	elif not sim.cells.has(b):
		route[-1] = to  # the exact spot, not the middle of its tile
	routes[id] = route


## Move someone along their route by `pace` and play the matching animation.
func _walk(id: String, pace: float) -> void:
	var n: Node3D = crew_nodes[id]
	var route: Array = routes[id]
	var moving := not route.is_empty() and pace > 0.0
	if moving:
		var to: Vector3 = route[0] - n.position
		n.position += to.limit_length(pace)
		if to.length() > 0.01:
			n.rotation.y = atan2(to.x, to.z)
		if to.length() <= pace:
			route.pop_front()
	_play(n, "walk" if moving else "idle")


## Pip walks to whatever was clicked last. Coworkers walk their beat: every so often on to the next building they look
## after, to stand beside it. None of them is part of the sim: where they stand changes nothing, their morale does.
## A coworker stays put while you talk to them, stands still while the game is paused, and goes back to the wall on a
## walkout day.
func _walk_crew(delta: float) -> void:
	_walk("pip", 4.0 * delta)
	for id in Data.CREW:
		if id == talking:
			routes[id] = []
		else:
			crew_wait[id] -= delta * speed
			if crew_wait[id] <= 0.0:
				crew_wait[id] = 10.0 + randf() * 10.0
				_send(id, _next_stop(id))
		_walk(id, 2.5 * delta if speed > 0.0 else 0.0)
	# nobody walks through or stands inside anybody else: anyone closer than PERSONAL to another is eased away
	var people: Array = crew_nodes.values()
	for i in people.size():
		for j in range(i + 1, people.size()):
			var gap: Vector3 = people[j].position - people[i].position
			if gap.length() < PERSONAL:
				var push := (gap.normalized() if gap.length() > 0.001 else Vector3.RIGHT) * (PERSONAL - gap.length()) * minf(1.0, 6.0 * delta)
				people[i].position -= push * 0.5
				people[j].position += push * 0.5


## The next place on a coworker's beat: a free tile beside one of their buildings, or home when there is none.
func _next_stop(id: String) -> Vector3:
	var spots := []
	var ground := Rect2i(Vector2i(-1, -1), sim.floor_size + Vector2i(2, 2))
	if not sim.walkout:
		for pos in sim.cells:
			if sim.cells[pos].kind in Data.CREW[id].beat:
				for d in Data.DIRS:
					if not sim.cells.has(pos + d) and ground.has_point(pos + d):
						spots.append(_center(pos).lerp(_center(pos + d), 0.85))
						break
	if spots.is_empty() or id == "sales":  # Penny keeps coming back to her phone
		spots.append(crew_home[id])
	crew_stop[id] = (crew_stop[id] + 1) % spots.size()
	var nudge := Data.CREW.keys().find(id) - 1.5  # so two people sent to the same tile do not stand inside each other
	var spot: Vector3 = spots[crew_stop[id]]
	var nudged := spot + Vector3(nudge * 0.4, 0, nudge * 0.25)
	return spot if sim.cells.has(Vector2i(floori(nudged.x), floori(nudged.z))) else nudged


## Loop an animation, or play one once and fall back to idle. Does nothing if that animation is already looping.
static func _play(n: Node3D, anim: String, once := false) -> void:
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	if once:
		ap.play(anim)
		ap.queue("idle")
	elif ap.current_animation != anim and not ap.current_animation.begins_with("emote"):
		ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		ap.play(anim)


func _camera(delta: float) -> void:
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1
		if Input.is_physical_key_pressed(KEY_D): move.x += 1
		if Input.is_physical_key_pressed(KEY_W): move.y -= 1
		if Input.is_physical_key_pressed(KEY_S): move.y += 1
		pivot += Basis(Vector3.UP, yaw * PI / 2 + PI / 4) * Vector3(move.x, 0, move.y) * delta * zoom
	pivot = pivot.clamp(Vector3(-2, 0, -2), Vector3(sim.floor_size.x + 2, 0, sim.floor_size.y + 2))
	var b := Basis(Vector3.UP, yaw * PI / 2 + PI / 4) * Basis(Vector3.RIGHT, deg_to_rad(-40))
	cam.transform = Transform3D(b, pivot + b.z * 60.0)
	cam.size = zoom


func _draw_items(frac: float) -> void:
	var n := {}
	for id in item_mm:
		n[id] = 0
	for pos in sim.cells:
		var c: Dictionary = sim.cells[pos]
		if c.get("item", "") == "":
			continue
		var at := _center(pos)
		if c.at == sim.ticks:  # it arrived this tick: slide it in from where it came
			at = _center(c.from).lerp(at, frac)
		var s: float = ITEM_LOOK[c.item][1]
		if n[c.item] < 1024:
			item_mm[c.item].set_instance_transform(n[c.item], Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3(0, 0.4, 0)))
			n[c.item] += 1
	for id in item_mm:
		item_mm[id].visible_instance_count = n[id]


func _draw_tags() -> void:
	var now := [cam.transform, zoom, sim.ticks, sim.cells.size(), crew_nodes.values().map(func(n): return n.position), sim.quest.get("step", -1)]
	if now != tags_seen:  # repaint only when the view or the factory changed
		tags_seen = now
		tag_canvas.queue_redraw()


## Paint every building's tag on one 2D overlay. They used to be a Label3D each, and a few hundred of those made the
## browser build draw no 3D at all (672 hoppers with labels: blank; without: fine).
func _paint_tags() -> void:
	var font := ThemeDB.fallback_font
	var size := clampi(int(260.0 / zoom), 10, 20)
	var taken: Array[Rect2] = []  # where tags already are: one that would land on another is nudged up a line
	# what the errand's current step wants is marked in orange: the coworker to talk to, the kind of building to look
	# at, or (for goods to ship) the outbound docks
	var step: Dictionary = sim.quest.steps[sim.quest.step] if not sim.quest.is_empty() else {}
	var wanted: String = step.get("target_id", "") if step.get("objective") != "deliver" else "outbound"
	for id in crew_nodes:  # people first: their names and morale, coloured by mood, at any zoom
		var label := "Pip (you)" if id == "pip" else "%s %d" % [Data.CREW[id].name, int(sim.morale[id])]
		var ink: Color = Color.WHITE if id == "pip" else {"low": Color.TOMATO, "mid": Color("ffe9a8"), "high": Color("9be8a4")}[sim.mood(id)]
		if step.get("objective") == "talk_to" and wanted == id:
			label = "> %s <" % label
			ink = ORANGE
		var spot := cam.unproject_position(crew_nodes[id].position + Vector3(0, 1.45, 0))
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		spot.x -= wide / 2
		var room := Rect2(spot.x, spot.y - size, wide, size)
		for tries in 4:  # people gather at the same dock: stack their names
			if taken.any(func(t): return t.intersects(room)):
				room.position.y -= size + 2
		spot.y = room.position.y + size
		taken.append(room)
		tag_canvas.draw_string_outline(font, spot, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color.BLACK)
		tag_canvas.draw_string(font, spot, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	if zoom > 26.0:  # too far out to read the buildings' tags: skip them, which also keeps a huge floor fast
		return
	var screen := tag_canvas.get_rect().grow(60)
	for pos in views:
		var c: Dictionary = sim.cells[pos]
		var at := cam.unproject_position(_center(pos) + Vector3(0, 2.0 if c.kind in ["inbound", "outbound"] else 1.4, 0))
		if not screen.has_point(at):
			continue
		var text := _tag_text(c)
		var marked: bool = step.get("objective", "talk_to") != "talk_to" and c.kind == wanted
		if marked:
			text = "> %s <" % (text if text != "" else Data.BUILD[c.kind].name)
		if text == "":
			continue
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		at.x -= width / 2
		var box := Rect2(at.x, at.y - size, width, size)
		for tries in 3:
			if taken.any(func(t): return t.intersects(box)):
				box.position.y -= size + 2
		at.y = box.position.y + size
		taken.append(box)
		tag_canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color.BLACK)
		tag_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ORANGE if marked else Color.WHITE)


## What floats over a building: what a dock handles, how full a hopper is, and for a machine only what is wrong.
func _tag_text(c: Dictionary) -> String:
	match c.kind:
		"inbound": return "IN: " + Data.ITEMS[c.raw].name
		"outbound": return "OUT"
		"hopper": return "%d/%d" % [c.store.size(), Data.HOPPER_CAP]
	if c.jam > 0:
		return "JAMMED"
	if c.out != "":
		return "blocked"
	if not c.busy:
		var need: Dictionary = Data.BUILD[c.kind]["in"]
		var missing: Array = need.keys().filter(func(i): return c.buf.get(i, 0) < need[i])
		if not missing.is_empty():
			return "needs " + " and ".join(missing.map(func(i): return Data.ITEMS[i].name))
	return ""


func _draw_ghost() -> void:
	var pos := _mouse_cell()
	var want := tool + str(tool_dir)
	if ghost_key != want:
		for ch in ghost.get_children():
			ch.queue_free()
		ghost_key = want
		if LOOK.has(tool):
			ghost.add_child(_model(tool, tool_dir))
			var arrow := MeshInstance3D.new()
			arrow.mesh = belt_mm.arrow.mesh
			arrow.transform = _arrow_at(_arrow_spot(tool, Vector3.ZERO, tool_dir), tool_dir)
			ghost.add_child(arrow)
	ghost.visible = LOOK.has(tool) and Rect2i(Vector2i.ZERO, sim.floor_size).has_point(pos)
	ghost.position = _center(pos) + Vector3(0, 0.05, 0)


func _mouse_cell() -> Vector2i:
	var p := _mouse_ground()
	return Vector2i(floori(p.x), floori(p.z))


func _mouse_ground() -> Vector3:
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	return o - d * (o.y / d.y)


# ---------- input ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP: zoom = maxf(6.0, zoom - 1.0)
			MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(40.0, zoom + 1.0)
			MOUSE_BUTTON_LEFT: _click(_mouse_cell())
			MOUSE_BUTTON_RIGHT:
				if tool != "":
					tool = ""
				else:
					_remove(_mouse_cell())
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT and tool in ["belt", "remove"]:
		_click(_mouse_cell())  # drag to lay a run of conveyor, or to clear one
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (e.button_mask & MOUSE_BUTTON_MASK_LEFT and tool == "")):
		# drag the floor to move the view (a finger does the same: touches arrive as the left button)
		pivot -= Basis(Vector3.UP, yaw * PI / 2 + PI / 4) * Vector3(e.relative.x, 0, e.relative.y * 1.5) * zoom / 700.0
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode if e.physical_keycode != 0 else e.keycode:  # some browsers and tools send no physical key
			KEY_R:
				if LOOK.has(tool):
					tool_dir = (tool_dir + 1) % 4
				else:
					sim.rotate(_mouse_cell())
					_refresh(_mouse_cell())
			KEY_Q: yaw = (yaw + 1) % 4
			KEY_E: yaw = (yaw + 3) % 4
			KEY_ESCAPE:
				tool = ""
				_close_talk()
			KEY_SPACE: speed = 0.0 if speed > 0.0 else 1.0
			KEY_M: AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
			KEY_N: music.stream_paused = not music.stream_paused
			KEY_F3: show_fps = not show_fps
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var n: int = (e.physical_keycode if e.physical_keycode != 0 else e.keycode) - KEY_1
				if n < build_buttons.size():
					tool = build_buttons.keys()[n]
					_sfx("click", -6.0)


func _remove(pos: Vector2i) -> void:
	if sim.cells.has(pos):
		_sfx("remove")
		sim.demolish(pos)
		_refresh(pos)


## The on-screen stand-in for the R key: turn the piece in hand, or with no tool the last building clicked.
func _turn() -> void:
	if LOOK.has(tool):
		tool_dir = (tool_dir + 1) % 4
	elif sim.cells.has(last_clicked):
		sim.rotate(last_clicked)
		_refresh(last_clicked)


func _click(pos: Vector2i) -> void:
	if tool == "remove":
		_remove(pos)
		return
	last_clicked = pos
	if tool != "":
		if sim.build(tool, pos, tool_dir):
			_refresh(pos)
			_sfx("place")
			if sim.cells.size() == 4:
				crew.refill()
		elif not sim.cells.has(pos) and sim.money < Data.BUILD[tool].cost:
			_toast("Not enough money for that.")
			_sfx("error")
		return
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	for id in crew_nodes:
		var to: Vector3 = crew_nodes[id].position + Vector3(0, 0.6, 0) - o
		if (to - d * to.dot(d)).length() < 0.7:  # the click's ray passes through this person
			if id == "pip":
				_toast("That's you: %s." % Data.PLAYER)
			else:
				_open_talk(id)
			return
	var c = sim.cells.get(pos)
	if c == null:
		return
	sim.quest_event("inspect", c.kind)
	_send("pip", _center(pos) + Vector3(0.0, 0, 0.8))
	if c.kind == "inbound":
		sim.cycle_raw(pos)
		_toast("This dock now orders %s (%d a crate)." % [Data.ITEMS[c.raw].name, Data.ITEMS[c.raw].buy])
	elif Data.BUILD[c.kind].has("in"):
		var b: Dictionary = Data.BUILD[c.kind]
		var held: Array = c.buf.keys().filter(func(i): return c.buf[i] > 0).map(func(i): return "%d %s" % [c.buf[i], Data.ITEMS[i].name])
		var state := "Jammed: Sprocket is on it." if c.jam > 0 else ("Blocked: nowhere to put what it made." if c.out != "" else
				("Working, %d%% done." % int(100.0 * c.prog / b.time) if c.busy else "Waiting for materials."))
		_toast("%s. %s\n%s Holding %s." % [b.name, _does(c.kind), state, ", ".join(held) if not held.is_empty() else "nothing"])
	else:
		_toast("%s. %s\nR turns it, right-click removes it for half its price." % [Data.BUILD[c.kind].name, _does(c.kind)])


# ---------- the interface ----------

func _box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	return s


func _button(text: String, parent: Node, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(Color("4a4870")))
	b.add_theme_stylebox_override("hover", _box(Color("5d5a8c")))
	b.add_theme_stylebox_override("pressed", _box(ORANGE))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_sfx.bind("click", -6.0))
	b.pressed.connect(act)
	parent.add_child(b)
	return b


func _panel(anchor: int, parent: Node, min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(INK, 0.92)))
	p.custom_minimum_size = min_size
	parent.add_child(p)
	p.grow_horizontal = {Control.PRESET_CENTER_RIGHT: Control.GROW_DIRECTION_BEGIN, Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END,
			Control.PRESET_BOTTOM_LEFT: Control.GROW_DIRECTION_END}.get(anchor, Control.GROW_DIRECTION_BOTH)
	p.grow_vertical = {Control.PRESET_BOTTOM_WIDE: Control.GROW_DIRECTION_BEGIN, Control.PRESET_TOP_WIDE: Control.GROW_DIRECTION_END,
			Control.PRESET_TOP_LEFT: Control.GROW_DIRECTION_END, Control.PRESET_BOTTOM_LEFT: Control.GROW_DIRECTION_BEGIN}.get(anchor, Control.GROW_DIRECTION_BOTH)
	p.set_anchors_and_offsets_preset(anchor, Control.PRESET_MODE_MINSIZE, 10)
	return p


func _ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	tag_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	tag_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_canvas.draw.connect(_paint_tags)
	root.add_child(tag_canvas)

	var bar := _panel(Control.PRESET_TOP_WIDE, root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	top = Label.new()
	row.add_child(top)
	day_bar = ProgressBar.new()
	day_bar.custom_minimum_size = Vector2(80, 0)
	day_bar.max_value = Data.TICKS_PER_DAY
	day_bar.show_percentage = false
	row.add_child(day_bar)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	contract_label = Label.new()
	contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(contract_label)
	quest_label = Label.new()
	quest_label.add_theme_color_override("font_color", ORANGE)
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(quest_label)
	net_label = Label.new()
	row.add_child(net_label)
	for s in [["||", 0.0], [">", 1.0], [">>", 2.0], [">>>", 4.0]]:
		speed_buttons[s[1]] = _button(s[0], row, func(): speed = s[1])
	_button("?", row, func(): _ask("[b]How to play[/b]\n" + HELP, [["Close", Callable()]], "sound"))
	new_game_button = _button("New game", row, _confirm_new_game)
	bar_toggle = _button("Build", row, func(): bar_open = not bar_open)

	bottom_panel = _panel(Control.PRESET_BOTTOM_WIDE, root)
	build_bar = HFlowContainer.new()
	bottom_panel.add_child(build_bar)
	mini = _panel(Control.PRESET_BOTTOM_LEFT, root)
	var mini_row := HBoxContainer.new()
	mini.add_child(mini_row)
	_button("Turn", mini_row, _turn)
	_button("Put away", mini_row, func(): tool = "")

	toast = Label.new()
	toast.add_theme_stylebox_override("normal", _box(Color(INK, 0.92)))
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.custom_minimum_size = Vector2(520, 0)
	root.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 80)
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast.hide()

	talk_panel = _panel(Control.PRESET_CENTER_RIGHT, root, Vector2(380, 420))
	var tv := VBoxContainer.new()
	talk_panel.add_child(tv)
	var head := HBoxContainer.new()
	tv.add_child(head)
	talk_face = TextureRect.new()
	talk_face.custom_minimum_size = Vector2(56, 56)
	talk_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	talk_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(talk_face)
	talk_title = Label.new()
	talk_title.add_theme_color_override("font_color", ORANGE)
	head.add_child(talk_title)
	talk_log = RichTextLabel.new()
	talk_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	talk_log.scroll_following = true
	tv.add_child(talk_log)
	raise_row = HBoxContainer.new()
	tv.add_child(raise_row)
	_button("Grant (+%d a day)" % Data.RAISE, raise_row, func(): _answer_raise(true))
	_button("Refuse", raise_row, func(): _answer_raise(false))
	var tb := HBoxContainer.new()
	tv.add_child(tb)
	_button("Any work?", tb, func(): _say_note(crew.offer_quest(talking)))
	_button("Offer a raise", tb, func(): raise_row.show())
	_button("Close", tb, _close_talk)
	talk_input = LineEdit.new()
	talk_input.placeholder_text = "Say something, then Enter"
	talk_input.max_length = 200
	talk_input.text_submitted.connect(_say)
	tv.add_child(talk_input)

	tut_panel = _panel(Control.PRESET_TOP_LEFT, root, Vector2(430, 0))
	tut_panel.offset_top = 120
	var uv := VBoxContainer.new()
	tut_panel.add_child(uv)
	tut_text = RichTextLabel.new()
	tut_text.bbcode_enabled = true
	tut_text.fit_content = true
	tut_text.add_theme_font_size_override("normal_font_size", 18)
	tut_text.add_theme_font_size_override("bold_font_size", 18)
	uv.add_child(tut_text)
	_button("Skip the tutorial", uv, func(): tutorial = TUTORIAL.size())

	modal_panel = _panel(Control.PRESET_CENTER, root, Vector2(480, 0))
	sideways = Label.new()
	sideways.text = "Hoppertunity needs a wide screen.\nPlease turn your device sideways."
	sideways.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sideways.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sideways.add_theme_font_size_override("font_size", 44)
	sideways.add_theme_stylebox_override("normal", _box(INK))
	sideways.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(sideways)  # after everything else, so it covers the game
	sideways.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sideways.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	modal_panel.add_child(dv)
	modal_text = RichTextLabel.new()
	modal_text.bbcode_enabled = true
	modal_text.fit_content = true
	modal_text.custom_minimum_size.x = 460  # a fixed width, so the text knows how tall it is
	dv.add_child(modal_text)
	chart.custom_minimum_size = Vector2(0, 90)
	chart.draw.connect(_paint_chart)
	dv.add_child(chart)
	for v in [["Music", "music_vol"], ["Sound effects", "sfx_vol"]]:
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = v[0]
		name_label.custom_minimum_size.x = 130
		line.add_child(name_label)
		var slider := HSlider.new()
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = get(v[1])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_set_volume.bind(v[1]))
		line.add_child(slider)
		sound_box.add_child(line)
	dv.add_child(sound_box)
	modal_buttons = VBoxContainer.new()
	dv.add_child(modal_buttons)


func _build_buttons() -> void:
	for ch in build_bar.get_children():
		ch.queue_free()
	build_buttons = {}
	for kind in Data.BUILD:
		if kind in sim.unlocked:
			# a card: the kit's own picture of the piece, its name, its price, and its number key (1 to 9)
			var key := "%d " % (build_buttons.size() + 1) if build_buttons.size() < 9 else ""
			var b := _button("%s%s\n%d coins" % [key, Data.BUILD[kind].name, Data.BUILD[kind].cost], build_bar, func(): tool = "" if tool == kind else kind)
			b.icon = load("res://assets/icons/%s.png" % kind)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.expand_icon = true
			b.custom_minimum_size = Vector2(104, 96)
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_color_override("icon_normal_color", LOOK[kind][2])
			b.add_theme_color_override("icon_hover_color", LOOK[kind][2])
			b.add_theme_color_override("icon_pressed_color", LOOK[kind][2])
			b.tooltip_text = _does(kind)
			build_buttons[kind] = b
	_button("Expand %d" % sim.expand_cost(), build_bar, _expand).tooltip_text = "Two more rows and columns of floor."
	_button("Upgrades", build_bar, _upgrades).tooltip_text = "One-off improvements to the whole plant."
	_button("Crew", build_bar, _crew_sheet).tooltip_text = "Everyone's morale, pay, errands and story at a glance."
	# everything the keyboard, wheel and right button do, for a touch screen or a one-button mouse
	_button("Turn", build_bar, _turn).tooltip_text = "Turn the piece in hand, or the building you last clicked (R)."
	remove_button = _button("Remove", build_bar, func(): tool = "" if tool == "remove" else "remove")
	remove_button.tooltip_text = "Click buildings to remove them for half their price (or right-click one with no tool in hand)."
	_button("+", build_bar, func(): zoom = maxf(6.0, zoom - 3.0)).tooltip_text = "Zoom in (mouse wheel)."
	_button("-", build_bar, func(): zoom = minf(40.0, zoom + 3.0)).tooltip_text = "Zoom out (mouse wheel)."
	_button("View", build_bar, func(): yaw = (yaw + 1) % 4).tooltip_text = "Turn the view a quarter (Q and E)."


## The four coworkers on one screen: what each is worth to the plant right now and how far their story has got.
func _crew_sheet() -> void:
	var lines := ["[b]The crew[/b]   team morale %d" % int(sim.team_morale()), ""]
	for id in Data.CREW:
		var c: Dictionary = Data.CREW[id]
		lines.append("[b]%s[/b], %s" % [c.name, c.role])
		lines.append("   morale %d (%s): their work runs at %d%%%s" % [int(sim.morale[id]), sim.mood(id), int(round(sim.mult(id) * 100.0)),
				"  [color=#f2a13c]fired up[/color]" if sim.boosts.has(id) else ""])
		lines.append("   wage %d a day, %d errand(s) done, story %d of 4%s" % [sim.wages[id], sim.quests_done[id], sim.beats_told[id],
				"  [color=#f2a13c]%s[/color]" % c.perk if sim.perks.has(id) else ""])
	lines.append("")
	lines.append("Under 30 on average they walk out for a day; over 70 everything sells for a tenth more. Talk, help with errands, pay fairly.")
	_ask("\n".join(lines), [["Close", Callable()]])


func _upgrades() -> void:
	var picks := []
	var owned := []
	for id in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[id]
		if id in sim.upgrades:
			owned.append(u.name)
		else:
			picks.append(["%s, %d coins: %s" % [u.name, u.cost, u.does], _buy.bind(id)])
	picks.append(["Close", Callable()])
	_ask("[b]Upgrades[/b]\nOne-off improvements to the whole plant. You have %d coins.%s" % [sim.money,
			"\nInstalled: " + ", ".join(owned) + "." if not owned.is_empty() else ""], picks)


func _buy(id: String) -> void:
	if sim.buy_upgrade(id):
		_toast("%s installed. %s" % [Data.UPGRADES[id].name, Data.UPGRADES[id].does])
		_sfx("win")
	else:
		_toast("Not enough money for the %s." % Data.UPGRADES[id].name.to_lower())
		_sfx("error")


## What a kind of building does, in a sentence: for the build bar's tooltips and for clicking on one.
func _does(kind: String) -> String:
	var b: Dictionary = Data.BUILD[kind]
	if b.has("does"):
		return b.does
	var needs: Array = b["in"].keys().map(func(i): return Data.ITEMS[i].name)
	return "Makes %s from %s. %s looks after it." % [Data.ITEMS[b.out].name, " and ".join(needs), Data.CREW[b.crew].name]


func _hud() -> void:
	top.text = "%d coins   Day %d   Crew morale %d" % [sim.money, sim.day, int(sim.team_morale())]
	if show_fps:
		top.text += "   %d fps, %d buildings" % [Engine.get_frames_per_second(), sim.cells.size()]
	day_bar.value = sim.tick
	var k: Dictionary = sim.contract
	contract_label.text = "Contract: %d/%d %s by the end of day %d, pays %d" % [k.done, k.qty, Data.ITEMS[k.item].name, k.due, k.reward]
	if sim.walkout:
		contract_label.text = "WALKOUT: the crew is too unhappy to work today.   " + contract_label.text
	if sim.bankrupt():
		contract_label.text = "BANKRUPT. The Hopper Works has closed its doors."
		if not told_bankrupt:
			told_bankrupt = true
			_ask("[font_size=24][b]The gates close[/b][/font_size]\n\nThe Hopper Works is %d coins in debt and the bank has called it in, on day %d."
					% [-sim.money, sim.day], [["New game", _new_game]])
	elif sim.won():
		contract_label.text = "The Works is saved.   " + contract_label.text
	if sim.offers.size() > 1 and not asked_offers:  # Penny has more than one customer: the player picks
		asked_offers = true
		var picks := []
		for i in sim.offers.size():
			var o: Dictionary = sim.offers[i]
			picks.append(["%s: %d %s by the end of day %d, pays %d" % [o.label, o.qty, Data.ITEMS[o.item].name, o.due, o.reward], sim.choose.bind(i)])
		_ask("[b]Penny has customers on the line.[/b]\nWhich contract do you take? The happier Penny is, the more she can line up.", picks)
	elif sim.offers.size() <= 1:
		asked_offers = false
	quest_label.visible = not sim.quest.is_empty() or sim.event.has("text")
	quest_label.text = "Today: " + sim.event.get("text", "")
	if not sim.quest.is_empty():
		var s: Dictionary = sim.quest.steps[sim.quest.step]
		quest_label.text = "Quest for %s: %s%s" % [Data.CREW[sim.quest.giver].name, s.get("description", ""),
				" (%d/%d)" % [sim.quest.have, sim.quest.need] if sim.quest.need > 1 else ""]
	net_label.text = "Anansi live" if crew.online else "Anansi offline"
	# The interface is laid out for 1280x720 and shrinks with the window. On a phone that leaves the text too small to
	# read or tap, so below about 85% size everything is scaled back up (and the bars wrap onto more rows).
	var window := Vector2(DisplayServer.window_get_size())
	var shrink := minf(window.x / 1280.0, window.y / 720.0)
	get_tree().root.content_scale_factor = clampf(0.85 / maxf(shrink, 0.01), 1.0, 1.8)
	var compact := shrink < 0.8  # no room for a build bar that is always open
	if tool != bar_tool:
		bar_tool = tool
		if tool != "":
			bar_open = false
	bar_toggle.visible = compact
	net_label.visible = not compact  # the top bar has no room for these on a phone; the title screen offers New game
	new_game_button.visible = not compact
	if compact:
		top.text = "%d coins  day %d\nmorale %d" % [sim.money, sim.day, int(sim.team_morale())]
	bar_toggle.text = "Close" if bar_open else "Build"
	bottom_panel.visible = not compact or bar_open
	mini.visible = compact and not bar_open and tool != ""
	var screen := get_viewport().get_visible_rect().size
	sideways.visible = screen.y > screen.x * 1.1
	for sp in speed_buttons:
		speed_buttons[sp].modulate = Color(1.6, 1.3, 0.8) if is_equal_approx(sp, speed) else Color.WHITE
	if modal:  # keep it as small as its content and in the middle; the container presets drift when the content changes
		modal_panel.size = Vector2(480, 0)
		modal_panel.position = ((modal_panel.get_parent() as Control).size - modal_panel.size) / 2
	_tutorial()


func _count(kind: String) -> int:
	return sim.cells.values().filter(func(c): return c.kind == kind).size()


func _tutorial_done(step: int) -> bool:
	match step:
		0: return sim.today.shipped >= 2 or sim.day > 1
		1: return _count("inbound") >= 2
		2: return _count("press") >= 2
		3: return _count("belt") >= 4
		4: return _count("outbound") >= 2
		5: return speed != 1.0
		6: return talking != ""
		7: return not sim.quest.is_empty() or sim.quests_done.values().max() > 0
	return sim.quests_done.values().max() > 0


## Show the current tutorial step, move on when it is done, pulse the build button it talks about and light up the
## floor tile it wants. Nothing shows while a question or report is up, so the two never compete.
func _tutorial() -> void:
	if tutorial < TUTORIAL.size() and _tutorial_done(tutorial):
		tutorial += 1
		_sfx("step")
	var on := tutorial < TUTORIAL.size()
	tut_panel.visible = on and not modal
	var want: String = TUTORIAL[tutorial][1] if on else ""
	if on:
		tut_text.text = "[color=#f2a13c]Getting started: %d of %d[/color]\n%s" % [tutorial + 1, TUTORIAL.size(), TUTORIAL[tutorial][0]]
	var glow := 0.75 + 0.5 * absf(sin(Time.get_ticks_msec() / 300.0))
	for kind in build_buttons:
		build_buttons[kind].modulate = Color(glow, glow, glow * 0.6) if kind == want else (Color(1.6, 1.3, 0.8) if kind == tool else Color.WHITE)
	remove_button.modulate = Color(1.7, 0.9, 0.8) if tool == "remove" else Color.WHITE
	var tile = TUTORIAL[tutorial][2] if on else null
	tut_marker.visible = tile != null and not sim.cells.has(tile)  # built somewhere else instead: the step still counts
	if tile != null:
		tut_marker.position = _center(tile) + Vector3(0, 0.04, 0)
		tut_marker.scale = Vector3.ONE * (0.85 + 0.1 * glow)


func _toast(text: String) -> void:
	toast.text = text
	toast.show()
	var mine := text
	await get_tree().create_timer(5.0).timeout
	if toast.text == mine:
		toast.hide()


## The vans are for show: the sim knows nothing of them. One drives off when TRUCK_LOAD crates have gone through its
## dock, and the next backs in.
func _truck_load(pos: Vector2i) -> void:
	var t = trucks.get(pos)
	if t == null or t.away:
		return
	t.count += 1
	if t.count < TRUCK_LOAD:
		return
	t.count = 0
	t.away = true
	var far: Vector3 = t.home + t.front * 9.0
	var tw := create_tween()
	tw.tween_property(t.node, "position", far, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.8)
	tw.tween_property(t.node, "position", t.home, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): t.away = false)


func _on_sold(pos: Vector2i, _item: String, amount: int) -> void:
	_truck_load(pos)
	if Time.get_ticks_msec() - last_sell > 180:
		last_sell = Time.get_ticks_msec()
		_sfx("sell" if amount > 0 else "error", -12.0)
	var l := Label3D.new()
	l.text = "+%d" % amount if amount > 0 else "returned!"
	l.modulate = ORANGE if amount > 0 else Color.TOMATO
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 40
	l.outline_size = 10
	l.position = _center(pos) + Vector3(0, 1.8, 0)
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", 3.0, 0.8)
	t.tween_callback(l.queue_free)


func _on_day_end(s: Dictionary) -> void:
	_sfx("day")
	_save()
	var lines := ["[b]End of day %d[/b]" % s.day, "",
			"Shipped: %d units%s" % [s.shipped, ", %d returned as defective" % s.defects if s.defects > 0 else ""],
			"Revenue: %d" % s.revenue, "Running costs: %d (wages, rent and upkeep %d, the rest materials)" % [s.costs, s.wages_rent],
			"[b]Profit: %+d[/b]" % (s.revenue - s.costs), "Spent on building: %d   Cash: %d" % [s.built, sim.money], ""]
	if s.walkout:
		lines.append("The crew stayed home today. A day off cleared the air a little.")
	if s.missed:
		lines.append("[color=tomato]The contract deadline was missed. The customer took a penalty and Penny took the call.[/color]")
	if s.event != "":
		lines.append("[color=#f2a13c]Tomorrow: %s[/color]" % s.event)
	if s.walkout_next:
		lines.append("[color=tomato]Morale is on the floor: the crew will not work tomorrow. Talk to them, help them, pay them.[/color]")
	for id in Data.CREW:
		lines.append("%s (%s): morale %d, wage %d" % [Data.CREW[id].name, Data.CREW[id].role, int(sim.morale[id]), sim.wages[id]])
	_ask("\n".join(lines), [["Start the next day", Callable()]], "chart")
	_day_remark(modal_queue[-1] if not modal_queue.is_empty() else modal_now, s)


## Whoever is feeling the day most (the lowest morale) says a word about it under the day's report, sentence by
## sentence as the gateway streams it. It is added to the report wherever that is: on screen or still waiting its turn.
func _day_remark(report: Dictionary, s: Dictionary) -> void:
	var who: String = Data.CREW.keys()[0]
	for id in Data.CREW:
		if sim.morale[id] < sim.morale[who]:
			who = id
	report.text += "\n\n[i]%s:[/i] " % Data.CREW[who].name
	if is_same(modal_now, report):
		modal_text.text = report.text
	var facts := "We shipped %d units, %d came back defective, and the plant made %d coins of profit.%s" % [s.shipped, s.defects,
			s.revenue - s.costs, " We missed the contract deadline." if s.missed else ""]
	await crew.remark(who, facts, func(sentence: String):
		report.text += sentence.replace("[", "(").replace("]", ")")  # a coworker's words are text, never markup
		if is_same(modal_now, report):
			modal_text.text = report.text)
	crew.refill()


# ---------- talking ----------

func _open_talk(id: String) -> void:
	talking = id
	tool = ""
	_send("pip", crew_nodes[id].position + Vector3(0.3, 0, 1.2))
	talk_title.text = "%s, %s" % [Data.CREW[id].name, Data.CREW[id].role]
	talk_face.texture = load("res://assets/icons/crew-%s.png" % id)
	talk_log.clear()
	raise_row.hide()
	talk_panel.show()
	talk_input.grab_focus()
	sim.quest_event("talk_to", id)
	_log(Data.CREW[id].name, crew.line(id))
	var beat := crew.story_beat(id)
	if beat != "":
		_log("", beat)


func _close_talk() -> void:
	talking = ""
	talk_panel.hide()
	talk_input.release_focus()


func _log(who: String, text: String) -> void:
	talk_log.add_text(("%s: " % who if who != "" else "~ ") + text + "\n\n")


func _say_note(note: String) -> void:
	if note != "":
		_log("", note)


func _say(text: String) -> void:
	text = text.strip_edges()
	if text == "" or talking == "":
		return
	var id := talking
	talk_input.text = ""
	talk_input.editable = false
	talk_input.placeholder_text = "%s is thinking..." % Data.CREW[id].name
	_log("Pip", text)
	var r: Dictionary = await crew.talk(id, text)
	talk_input.editable = true
	talk_input.placeholder_text = "Say something, then Enter"
	if talking != id:
		return
	talk_input.grab_focus()
	_log(Data.CREW[id].name, r.say)
	_say_note(r.note)
	_sfx("talk")
	if r.note.contains("morale"):
		_play(crew_nodes[id], "emote-yes" if r.note.contains("rises") else "emote-no", true)
		_sfx("up" if r.note.contains("rises") else "down")
	if r.raise:
		_log("", "%s is asking for a raise." % Data.CREW[id].name)
		raise_row.show()


func _answer_raise(grant: bool) -> void:
	raise_row.hide()
	sim.answer_raise(talking, grant)
	_sfx("up" if grant else "down")
	_play(crew_nodes[talking], "emote-yes" if grant else "emote-no", true)
	_log("", "You %s. %s's wage is %d a day." % ["agree" if grant else "say no", Data.CREW[talking].name, sim.wages[talking]])
