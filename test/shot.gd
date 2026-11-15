## Developer aid, not a check: runs the real game with a small factory, saves a screenshot and quits.
## It starts from a new game, so it deletes the desktop save (user://hoppertunity.json).
## Run (needs a display): godot --path . --script res://test/shot.gd -- out.png [seconds] [talk|-] [x,z,zoom]
extends SceneTree


func _init() -> void:
	go.call_deferred()


func go() -> void:
	DirAccess.remove_absolute("user://hoppertunity.json")
	var g: Node = load("res://main.tscn").instantiate()
	root.add_child(g)
	var s: Sim = g.sim
	if "title" not in OS.get_cmdline_user_args():
		g._next_modal()  # past the title screen
	s.money = 5000
	s.unlocked = Data.BUILD.keys() + Data.ITEMS.keys()
	var plan := [["inbound", 1, 2, 0], ["belt", 2, 2, 0], ["splitter", 3, 2, 0], ["belt", 4, 2, 0], ["press", 5, 2, 0], ["belt", 6, 2, 0],
			["assembler", 7, 2, 0], ["belt", 8, 2, 0], ["packer", 9, 2, 0], ["belt", 10, 2, 0], ["outbound", 11, 2, 0],
			["belt", 3, 3, 1], ["hopper", 3, 4, 1], ["belt", 3, 5, 1], ["belt", 3, 6, 0], ["belt", 4, 6, 0], ["outbound", 5, 6, 0],
			["inbound", 7, 5, 3], ["molder", 7, 4, 3], ["belt", 7, 3, 3], ["inbound", 9, 4, 3], ["belt", 9, 3, 3],
			["inbound", 13, 6, 3], ["belt", 13, 5, 3], ["belt", 13, 4, 2], ["belt", 12, 4, 2], ["belt", 11, 4, 1], ["belt", 11, 5, 1],
			["belt", 11, 6, 0], ["belt", 12, 6, 1], ["outbound", 12, 7, 1],
			["inbound", 1, 9, 0], ["winder", 2, 9, 0], ["belt", 3, 9, 0], ["fitter", 4, 9, 0], ["outbound", 5, 9, 0]]
	for p in plan:
		s.build(p[0], Vector2i(p[1], p[2]), p[3])
		g._refresh(Vector2i(p[1], p[2]))
	s.cycle_raw(Vector2i(7, 5))
	s.cycle_raw(Vector2i(9, 4))
	s.cycle_raw(Vector2i(9, 4))
	s.cells[Vector2i(1, 9)].raw = "copper"
	g._build_buttons()
	g.speed = 4.0
	g.tool = "press"
	g.tutorial = 99
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		var v := args[3].split_floats(",")
		g.pivot = Vector3(v[0], 0, v[1])
		g.zoom = v[2]
	await create_timer(float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 6.0).timeout
	if args.size() > 2 and args[2] == "walk":  # check nobody is standing inside a building after walking their beat
		var inside := 0
		for id in g.crew_nodes:
			var p: Vector3 = g.crew_nodes[id].position
			inside += int(s.cells.has(Vector2i(floori(p.x), floori(p.z))))
		print("people inside buildings: ", inside)
	if args.size() > 2 and args[2] == "offers":  # a happy Penny and a contract about to finish: the choice comes up
		s.morale.sales = 80.0
		s.contract = {"item": "boxed", "qty": 1, "done": 0, "due": 9, "reward": 100}
		await create_timer(3.0).timeout
		print("offers ", s.offers.size(), " modal ", g.modal, " asked ", g.asked_offers, " sales ", s.morale.sales, " done ", s.contracts_done,
				" panel ", g.modal_panel.visible, g.modal_panel.get_rect(), " buttons ", g.modal_buttons.get_child_count(), " queue ", g.modal_queue.size())
	if args.size() > 2 and args[2] == "upgrades":
		s.event = s.settle_event(Data.EVENTS[4])
		g._upgrades()
		await create_timer(0.5).timeout
	if args.size() > 2 and args[2] == "quest":
		s.start_quest(Data.QUESTS.dock[1], "dock")  # look in the hoppers, then talk to Sprocket, then Dot
		await create_timer(0.5).timeout
	if args.size() > 2 and args[2] == "crew":
		g._crew_sheet()
		await create_timer(0.5).timeout
	if args.size() > 2 and args[2] == "talk":
		g.tool = ""
		g._open_talk("tech")
		g._answer_raise(true)
		await create_timer(0.7).timeout
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
