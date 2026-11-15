## Self-checks for the sim and the crew layer. Prints "<n> failed" last.
## The HTTP checks pass with or without a gateway: with one they exercise the live path, without one the fallback path.
## HOP_GATEWAY sets its address (default http://127.0.0.1:8080); HOP_REQUIRE_LIVE=1 (CI) fails the run if it did not answer.
## The gateway must serve the "hoppertunity" title on mock nodes (tools/mock_node.py), which echo a scripted reply.
extends Node

var failed := 0


func ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
	print("ok   " if cond else "FAIL ", what)


## A sim with a row of buildings starting at (0, 0) and running east.
func line(kinds: Array, money := 100000) -> Sim:
	var s := Sim.new()
	s.money = money
	s.unlocked = Data.BUILD.keys() + Data.ITEMS.keys()
	for i in kinds.size():
		s.build(kinds[i], Vector2i(i, 0), 0)
	return s


func run_ticks(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func items_on(s: Sim) -> int:
	return s.cells.values().filter(func(c): return c.get("item", "") != "").size()


func run() -> int:
	# --- flow ---
	var s := line(["inbound", "belt", "belt", "belt", "outbound"])
	run_ticks(s, 60)
	ok(s.today.shipped > 5, "crates travel dock -> belts -> dock (%d shipped)" % s.today.shipped)
	ok(s.today.revenue == s.today.shipped * 1, "raw steel sells for 1 each at morale 50")

	s = line(["inbound", "belt", "belt", "belt"])
	run_ticks(s, 100)
	ok(items_on(s) == 3, "a blocked line fills up and loses nothing")
	var spent: int = 100000 - s.money - 100 - 15
	ok(spent == 3 * 2, "the dock only charges for crates it could unload")

	# --- machines ---
	s = line(["inbound", "press", "belt", "outbound"])
	run_ticks(s, 120)
	ok(s.contract.done > 5, "press turns steel into panels, and panels count for the contract (%d)" % s.contract.done)

	s = Sim.new()
	s.money = 100000
	s.unlocked = Data.BUILD.keys() + Data.ITEMS.keys()
	s.build("inbound", Vector2i(0, 0), 0)
	s.build("press", Vector2i(1, 0), 0)
	s.build("assembler", Vector2i(2, 0), 0)
	s.build("outbound", Vector2i(3, 0), 0)
	s.build("inbound", Vector2i(2, 2), 3)
	s.cycle_raw(Vector2i(2, 2))
	s.build("molder", Vector2i(2, 1), 3)
	var got := {}
	s.sold.connect(func(_p, item, _a): got[item] = got.get(item, 0) + 1)
	run_ticks(s, 200)
	ok(got.get("gadget", 0) > 3 and got.size() == 1, "assembler joins panels and casings into gadgets %s" % got)

	s = line(["inbound", "winder", "belt", "outbound"])
	s.cells[Vector2i(0, 0)].raw = "copper"
	s.morale.qa = 100.0
	run_ticks(s, 120)
	ok(s.today.shipped > 5 and s.today.revenue == s.today.shipped * 12, "the coil winder turns copper wire into coils (%d)" % s.today.shipped)
	var chains := true
	for kind in Data.BUILD:  # every recipe's inputs must be things something makes or a dock can order
		for item in Data.BUILD[kind].get("in", {}):
			chains = chains and (Data.ITEMS[item].has("buy") or Data.BUILD.values().any(func(b): return b.get("out") == item))
	for u in Data.UNLOCKS:
		for id in u:
			chains = chains and (Data.BUILD.has(id) or Data.ITEMS.has(id))
	for k in Data.CONTRACTS:
		chains = chains and Data.BUILD.values().any(func(b): return b.get("out") == k.item)
	ok(chains, "every recipe, unlock and contract names things that exist and can be made")

	s = line(["inbound", "splitter", "belt", "outbound"])
	s.build("belt", Vector2i(1, 1), 1)
	s.build("hopper", Vector2i(1, 2), 1)
	run_ticks(s, 100)
	var a: int = s.today.shipped
	var b: int = s.cells[Vector2i(1, 2)].store.size()
	ok(absi(a - b) <= 2 and a > 3, "splitter shares crates between its outputs (%d ahead, %d right)" % [a, b])

	s = line(["inbound", "hopper"])
	run_ticks(s, 400)
	ok(s.cells[Vector2i(1, 0)].store.size() == Data.HOPPER_CAP, "a hopper with no way out fills to its cap and stops the dock")

	# --- morale ---
	var out := []
	for m in [0.0, 100.0]:
		s = line(["inbound", "press", "outbound"])
		s.morale.tech = m
		s.morale.qa = 100.0
		run_ticks(s, 200)
		out.append(s.today.shipped)
	ok(out[1] > out[0], "a happy technician's press makes more (%d vs %d)" % [out[1], out[0]])

	s = Sim.new()
	for i in 5:
		s.apply_action("tech", "morale_up")
	ok(s.morale.tech == 60.0, "talk moves morale at most %d a day" % Data.MORALE_DAILY_CAP)
	ok(s.apply_action("tech", "launch_rocket") == "" and s.morale.tech == 60.0, "an unknown action does nothing")
	ok(s.apply_action("sales", "share_tip").contains("casings"), "a tip reveals the next contract")
	s.answer_raise("dock", true)
	ok(s.wages.dock == 20 and s.morale.dock == 65.0, "a raise costs wages and lifts morale")

	s = line(["inbound", "press", "outbound"])
	s.morale.qa = 0.0
	run_ticks(s, 200)
	ok(s.today.defects > 0, "an unhappy quality lead means returned units (%d)" % s.today.defects)

	s = Sim.new()
	for id in s.morale:
		s.morale[id] = 10.0
	run_ticks(s, Data.TICKS_PER_DAY)
	ok(s.walkout and s.day == 2, "a miserable crew walks out the next day")
	s.build("inbound", Vector2i(0, 0), 0)
	s.build("belt", Vector2i(1, 0), 0)
	run_ticks(s, 30)
	ok(items_on(s) == 0, "nothing moves during a walkout")

	# --- contracts and money ---
	s = line(["inbound", "press", "outbound"], 1000)
	s.unlocked = Data.START_UNLOCKS.duplicate()
	s.morale.qa = 100.0
	s.contract.qty = 3
	run_ticks(s, 100)
	ok(s.contracts_done == 1 and "molder" in s.unlocked and s.contract.item == "casing", "finishing a contract unlocks the next machine")

	for mood in [[20.0, 1], [50.0, 2], [80.0, 3]]:
		s = line(["inbound", "press", "outbound"], 1000)
		s.morale.qa = 100.0
		s.morale.sales = mood[0]
		s.contract.qty = 2
		run_ticks(s, 60)
		ok(s.offers.size() == mood[1] and s.contract == s.offers[0], "Penny at morale %d lines up %d contract(s)" % [mood[0], mood[1]])
	var bulk: Dictionary = s.offers[2]
	s.choose(2)
	ok(s.contract == bulk and bulk.qty == 45 and bulk.reward == 700 and s.offers.is_empty(), "choosing the bulk order swaps the contract (%d %s for %d)" % [bulk.qty, bulk.item, bulk.reward])

	# --- upgrades and events ---
	s = Sim.new()
	s.money = 1000
	ok(not s.buy_upgrade("showroom") and s.buy_upgrade("breakroom") and not s.buy_upgrade("breakroom") and s.money == 200,
			"an upgrade is bought once, and only with the money for it")
	run_ticks(s, Data.TICKS_PER_DAY)
	ok(s.morale.tech == 50.0 - Data.MORALE_WEAR + 1.0, "the break room slows the daily wear")
	out = []
	for tooled in [false, true]:
		s = line(["inbound", "press", "outbound"])
		s.morale.qa = 100.0
		if tooled:
			s.buy_upgrade("tooling")
		run_ticks(s, 200)
		out.append(s.today.shipped)
	ok(out[1] > out[0], "better tooling makes more (%d vs %d)" % [out[1], out[0]])
	var all_ok := true
	for e in Data.EVENTS:  # every event must name real coworkers and carry the words for both outcomes
		all_ok = all_ok and e.has("text") and (not e.has("saved_by") or (Data.CREW.has(e.saved_by) and e.has("saved")))
		for id in e.get("speed", {}):
			all_ok = all_ok and Data.CREW.has(id)
	ok(all_ok, "every event is well formed")
	s = Sim.new()
	s.event = s.settle_event(Data.EVENTS[0])
	ok(is_equal_approx(s.mult("dock"), 0.7) and is_equal_approx(s.mult("tech"), 1.0), "a late truck slows the docks for the day")
	s.morale.dock = 75.0
	s.event = s.settle_event(Data.EVENTS[0])
	ok(not s.event.has("speed") and s.event.text == Data.EVENTS[0].saved, "a happy Dot heads the late truck off")
	s.event = s.settle_event(Data.EVENTS[2])
	ok(s.money == Data.START_MONEY - 60, "a fine comes out of the till")

	s = Sim.new()
	var m0 := s.money
	run_ticks(s, Data.TICKS_PER_DAY * 2)
	ok(s.money == m0 - 2 * (Data.RENT + 60) - 50 and s.contract.due == 4, "a missed contract costs a penalty and is offered again")
	var walked := [false]
	s.day_ended.connect(func(sum): walked[0] = walked[0] or sum.walkout_next)
	run_ticks(s, Data.TICKS_PER_DAY * 10)
	ok(walked[0], "leave the crew alone for two weeks and they walk out")
	s.money = Data.BANKRUPT_AT - 1
	ok(s.bankrupt(), "deep enough in debt is bankruptcy")

	# --- quests and stories ---
	var all_start := true
	for id in Data.QUESTS:
		for q in Data.QUESTS[id]:
			all_start = all_start and Sim.new().start_quest(q, id)
	ok(all_start, "every authored quest only names things the game has")
	s = Sim.new()
	ok(not s.start_quest({"title": "x", "reward_tier": "small", "steps": [{"objective": "talk_to", "target_id": "nobody"}]}, "dock"),
			"a quest that names something unknown is refused")
	s.start_quest(Data.QUESTS.tech[0], "tech")
	m0 = s.money
	s.quest_event("talk_to", "tech")  # out of order: ignored
	s.quest_event("inspect", "press")
	s.quest_event("talk_to", "tech")
	ok(s.quest.is_empty() and s.money == m0 + 60 and s.morale.tech == 55.0 and s.quests_done.tech == 1, "a finished quest pays its tier")

	s = Sim.new()
	s.start_quest(Data.QUESTS.tech[1], "tech")  # a medium errand: ship panels, then talk to Sprocket
	for i in Data.DELIVER_QTY.medium:
		s.quest_event("deliver", "panel")
	s.quest_event("talk_to", "tech")
	var fired := s.mult("tech")
	run_ticks(s, Data.TICKS_PER_DAY)
	var still := s.boosts.has("tech")
	run_ticks(s, Data.TICKS_PER_DAY)
	ok(s.quest.is_empty() and is_equal_approx(fired, (0.8 + 0.4 * 0.58) * Data.BOOST) and still and not s.boosts.has("tech") and s.last_reward.boost == 1,
			"a medium errand leaves its giver fired up for the rest of the day and the next")

	s = Sim.new()
	ok(s.next_beat("qa") == 0, "the first story beat is ready at once")
	s.tell_beat("qa")
	ok(s.next_beat("qa") == -1, "the next beat waits for a finished quest")
	s.quests_done.qa = 3
	for i in 3:
		s.tell_beat("qa")
	ok(s.perks.has("qa"), "a finished storyline gives its perk")

	# --- saving ---
	s = line(["inbound", "splitter", "press", "belt", "outbound"])
	s.build("hopper", Vector2i(1, 1), 1)
	s.start_quest(Data.QUESTS.dock[0], "dock")
	run_ticks(s, 150)
	var t := Sim.new()
	t.restore(JSON.parse_string(JSON.stringify(s.save())))
	t.rng.state = s.rng.state
	run_ticks(s, 400)
	run_ticks(t, 400)
	ok(t.money == s.money and t.day == s.day and JSON.stringify(t.save()) == JSON.stringify(s.save()), "a saved game continues exactly as the original")

	# --- balance: one production line built in a sensible order (the bot in play() below) ---
	var kind := play(true)
	var cold := play(false)
	print("     caring manager: %s" % kind)
	print("     neglectful one: %s" % cold)
	var far := play(true, true)
	print("     playing on:     %s" % far)
	ok(far.contracts == 7 and far.day <= 20 and far.low >= 0 and far.upgrades >= 3 and far.money < 5000,
			"playing on (biggest orders, upgrades, the third line) reaches the seventh contract in three weeks without a cash mountain")
	ok(kind.won and kind.day <= 12 and kind.low >= 0 and kind.missed == 0, "a manager who looks after the crew saves the plant in under two weeks, never in debt")
	ok(cold.walkouts > 0 and (not cold.won or cold.day > kind.day or cold.missed > 0), "ignoring the crew ends in a walkout and costs time")

	# --- size: the largest floor, every cell a moving belt (rows joined into one long snake that ends in a dock) ---
	s = Sim.new()
	s.money = 1000000
	s.floor_size = Vector2i(28, 24)
	s.unlocked = Data.BUILD.keys() + Data.ITEMS.keys()
	for y in 24:
		for x in 28:
			var east := y % 2 == 0
			var end := x == (27 if east else 0)
			s.build("belt", Vector2i(x, y), 1 if end else (0 if east else 2))
	s.demolish(Vector2i(0, 0))
	s.build("inbound", Vector2i(0, 0), 0)
	s.demolish(Vector2i(0, 23))
	s.build("outbound", Vector2i(0, 23), 0)
	s.demolish(Vector2i(1, 23))
	s.build("belt", Vector2i(1, 23), 2)
	for id in s.morale:
		s.morale[id] = 100.0
	run_ticks(s, 700)
	var t0 := Time.get_ticks_usec()
	run_ticks(s, 200)
	var ms := (Time.get_ticks_usec() - t0) / 200000.0
	print("     %d cells, %d crates moving, %.2f ms a tick" % [s.cells.size(), items_on(s), ms])
	ok(s.today.shipped > 0 and items_on(s) > 100 and ms < 25.0, "a full 28x24 floor of belts ticks well inside a 250 ms tick, even at 4x speed")

	# --- crew: what an answer may do (a scripted Anansi, so every action is exercised) ---
	s = Sim.new()
	var crew := Crew.new()
	var fake := Scripted.new()
	crew.api = fake
	add_child(crew)
	crew.setup(s, "http://127.0.0.1:1", "hoppertunity", "x", "ci")
	fake.next = "morale_up"
	var r: Dictionary = await crew.talk("tech", "Good work on the press today.")
	ok(s.morale.tech == 55.0 and r.note != "", "a kind word the model rewards lifts morale")
	fake.next = "fire_everyone"
	r = await crew.talk("tech", "hello")
	ok(r.note == "" and s.morale.tech == 55.0 and s.money == Data.START_MONEY, "an action outside the whitelist is dropped")
	fake.next = "ask_raise"
	r = await crew.talk("tech", "How is the pay?")
	ok(r.raise and s.wages.tech == 15, "a raise is the player's decision, not the model's")
	fake.next = "offer_quest"
	r = await crew.talk("tech", "Anything I can do?")
	ok(r.note.begins_with("New quest") and s.quest.giver == "tech", "offer_quest starts that coworker's quest")
	var w := crew._world()
	s.build("inbound", Vector2i(0, 0), 0)
	var w2 := crew._world()
	ok(w.locations.size() == 6 and w2.locations.size() == 1 and w2.locations[0].id == "inbound" and w.items == [{"id": "panel", "name": "steel panels"}],
			"a quest may only name buildings on the floor and goods the plant makes")
	ok(crew.history.tech.size() == 6 and fake.seen[0].role == "system" and "Sprocket" in fake.seen[0].content,
			"the coworker gets a brief of who they are, and the last three exchanges")

	var heard := []
	crew.online = false
	r = await crew.remark("tech", "We shipped 30 units.", func(part): heard.append(part))
	ok(heard.size() == 1 and r.source == "fallback", "with the gateway down a day-end remark is a written line, at once")
	heard.clear()
	crew.online = true
	r = await crew.remark("tech", "We shipped 30 units.", func(part): heard.append(part))
	ok(heard == ["Busy day. ", "Bertha held up."] and r.say == "".join(heard), "with it up, the remark arrives sentence by sentence")

	# --- crew over HTTP: with a gateway on 127.0.0.1:8080 the live path, without one the fallback ---
	s = Sim.new()
	crew = Crew.new()
	add_child(crew)
	var url := OS.get_environment("HOP_GATEWAY") if OS.has_environment("HOP_GATEWAY") else "http://127.0.0.1:8080"
	var live := OS.get_environment("HOP_REQUIRE_LIVE") == "1"
	crew.setup(s, url, "hoppertunity", "change-me", "ci")
	crew.api.timeout_s = 5.0
	r = await crew.talk("tech", 'echo: {"say": "Bertha is purring, boss.", "action": "morale_up"}')
	print("     chat source: ", r.source)
	ok(r.say != "" and (r.source == "gateway" or not live), "a coworker always answers (%s)" % r.say)
	ok(s.morale.tech == 50.0, "typing an action's name does not trigger it")

	crew.api.generation_timeout_s = 10.0
	await crew.refill()
	print("     quests generated by the gateway: ", crew.queued.size())
	ok(crew.queued.size() == 4 or not live, "the gateway generates a quest for every coworker")
	var note := crew.offer_quest("dock")
	ok(note.begins_with("New quest") and not s.quest.is_empty() and s.quest.giver == "dock", "a coworker hands out a quest, generated or authored (%s)" % s.quest.title)
	ok(crew.offer_quest("tech").begins_with("Finish"), "one quest at a time")
	ok(crew.story_beat("dock") != "" and crew.story_beat("dock") == "", "a coworker tells one story beat, then waits")

	# --- the game itself: main.tscn driven through its screens. Headless nothing is drawn, but every handler runs, and
	# a script error anywhere in it fails CI (which greps the log for "SCRIPT ERROR") ---
	DirAccess.remove_absolute("user://hoppertunity_check.json")
	var g: Node = load("res://main.tscn").instantiate()
	g.save_path = "user://hoppertunity_check.json"  # never the player's own save
	add_child(g)
	ok(g.modal and g.sim.day == 1, "the game opens on its title screen")
	g._next_modal()
	var col := 2
	for piece in ["inbound", "press", "belt", "outbound"]:
		g.tool = piece
		g._click(Vector2i(col, 3))
		col += 1
	g.tool = ""
	g.sim.morale.qa = 100.0
	for i in 5:
		await get_tree().process_frame
	ok(g.sim.cells.size() == 4 and g.views.size() == 3 and g.belt_mm.belt.instance_count == 1 and g.tutorial >= 3,
			"clicking builds a line: three building nodes, one batched conveyor, and the tutorial follows along")
	run_ticks(g.sim, Data.TICKS_PER_DAY * 2)
	for i in 3:
		await get_tree().process_frame
	for i in 60:  # the remark is asked for over HTTP: give the refusal up to 15 s to come back
		if not g.modal_now.text.ends_with("[/i] "):
			break
		await get_tree().create_timer(0.25).timeout
	ok(g.modal_now.text.contains("End of day 1") and g.modal_now.text.contains("[i]") and not g.modal_now.text.ends_with("[/i] "),
			"the day's report carries a coworker's remark (a written one, with no gateway)")
	ok(g.sim.day == 3 and g.sim.contracts_done == 1 and g.modal and g.modal_queue.size() >= 1 and FileAccess.file_exists("user://hoppertunity_check.json"),
			"two days pass: day-end reports queue up, the first contract ships, the game is saved")
	while g.modal:
		g._next_modal()
	g.speed = 0.0  # paused: a real gateway takes half a minute to answer, and no day may end under the checks below
	g._click(Vector2i(3, 3))
	g._open_talk("tech")
	await g._say("Good work today.")
	g._say_note(g.crew.offer_quest("tech"))
	g._answer_raise(true)
	ok(g.talk_panel.visible and g.sim.quest.giver == "tech" and g.sim.wages.tech == 20
			and (g.routes.pip.size() > 0 or g.crew_nodes.pip.position.distance_to(g.crew_home.pip) > 0.5),
			"talking works with no gateway: a written line, an errand, a raise, and Pip walks over")
	g._click(Vector2i(3, 3))  # the errand is "Bertha's rattle": look at the press, then tell Sprocket
	g._open_talk("tech")
	ok(g.sim.quest.is_empty() and g.sim.quests_done.tech == 1 and g.toast.text.begins_with("Errand done"),
			"doing what the errand asks, by clicking, finishes it and says what it paid")
	g._close_talk()
	g.sim.money = 5000  # the purchases below must not depend on how the two days went
	g._upgrades()
	g._next_modal()
	g._buy("breakroom")
	g._crew_sheet()
	g._next_modal()
	g._expand()
	g.sim.rotate(Vector2i(4, 3))
	g._refresh(Vector2i(4, 3))
	g.sim.demolish(Vector2i(4, 3))
	g._refresh(Vector2i(4, 3))
	for i in 3:
		await get_tree().process_frame
	ok("breakroom" in g.sim.upgrades and g.sim.floor_size == Vector2i(18, 14) and g.belt_mm.belt.instance_count == 0 and not g.modal,
			"upgrades, the crew sheet, a bigger floor and removing a conveyor all go through")
	var s2 := Sim.new()
	var old: Dictionary = g.sim.save()
	old.today.erase("built")
	ok(g.sim.today.has("built"), "a saved copy can be changed without touching the running game")
	s2.restore(JSON.parse_string(JSON.stringify(old)))
	ok(s2.build("belt", Vector2i(9, 9), 0), "a save from before building spend was tracked still loads and plays")
	g.crew_nodes.dock.position = g.crew_nodes.tech.position
	g.routes.dock = []
	g.routes.tech = []
	g.crew_wait.dock = 99.0
	g.crew_wait.tech = 99.0
	await get_tree().create_timer(1.5).timeout  # by the clock, not by frames: a fast machine's frames are short
	ok(g.crew_nodes.dock.position.distance_to(g.crew_nodes.tech.position) > g.PERSONAL * 0.8, "two people on the same spot step apart")
	g.tool = "belt"
	g._click(Vector2i(10, 10))
	g.tool = ""
	g._click(Vector2i(10, 10))
	g._turn()
	var turned: int = g.sim.cells[Vector2i(10, 10)].dir
	g.tool = "remove"
	g._click(Vector2i(10, 10))
	ok(turned == 1 and not g.sim.cells.has(Vector2i(10, 10)), "the Turn and Remove buttons do what R and the right button do")
	g.tool = "belt"
	g._click(Vector2i(10, 10))
	g._confirm_new_game()
	g._answer(g._new_game)
	for i in 3:
		await get_tree().process_frame
	ok(g.sim.cells.is_empty() and g.sim.day == 1 and g.views.is_empty() and g.belt_mm.belt.instance_count == 0 and g.belt_mm.arrow.instance_count == 0
			and not FileAccess.file_exists("user://hoppertunity_check.json"), "a new game clears the floor, the screen and the save")
	g.queue_free()
	DirAccess.remove_absolute("user://hoppertunity_check.json")

	print("%d failed" % failed)
	return failed


## A whole game played by a fixed build order. Each stage: contracts needed, cash needed, cells to clear, then
## [kind, x, y, dir, times to switch the dock's material]. With care, the bot gives a raise to anyone whose morale sags.
func play(care: bool, late := false) -> Dictionary:
	var stages := [
		[0, 0, [], [["inbound", 0, 2, 0, 0], ["press", 1, 2, 0, 0], ["belt", 2, 2, 0, 0], ["outbound", 3, 2, 0, 0]]],
		[1, 400, [], [["inbound", 3, 5, 3, 1], ["molder", 3, 4, 3, 0], ["outbound", 3, 3, 0, 0]]],
		[2, 420, [[3, 2], [3, 3]], [["assembler", 3, 2, 0, 0], ["belt", 3, 3, 3, 0], ["belt", 4, 2, 0, 0], ["outbound", 5, 2, 0, 0]]],
		[3, 470, [[5, 2]], [["packer", 5, 2, 0, 0], ["belt", 6, 2, 0, 0], ["outbound", 7, 2, 0, 0], ["inbound", 5, 4, 3, 2], ["belt", 5, 3, 3, 0]]],
		# after the win: a coil line of its own, then the packer gives way to a fitter fed by that line
		[4, 700, [], [["inbound", 0, 8, 0, 3], ["winder", 1, 8, 0, 0], ["belt", 2, 8, 0, 0], ["outbound", 3, 8, 0, 0]]],
		[6, 600, [[5, 2], [5, 3], [5, 4], [3, 8]], [["fitter", 5, 2, 0, 0], ["belt", 3, 8, 0, 0], ["belt", 4, 8, 0, 0], ["belt", 5, 8, 3, 0],
			["belt", 5, 7, 3, 0], ["belt", 5, 6, 3, 0], ["belt", 5, 5, 3, 0], ["belt", 5, 4, 3, 0], ["belt", 5, 3, 3, 0]]],
	]
	var goal := 7 if late else Data.WIN_CONTRACTS
	var last_day := 30 if late else 20
	var s := Sim.new(7)
	var stage := 0
	var r := {"won": false, "day": 0, "money": 0, "low": s.money, "missed": 0, "raises": 0, "walkouts": 0, "upgrades": 0, "done_on": []}
	s.day_ended.connect(func(sum):
		r.missed += int(sum.missed)
		r.walkouts += int(sum.walkout_next))
	while s.contracts_done < goal and not s.bankrupt() and s.day <= last_day:
		if r.done_on.size() < s.contracts_done:
			r.done_on.append(s.day)
		if late and s.offers.size() > 1:  # the late-game manager takes the biggest order going
			s.choose(s.offers.size() - 1)
		if late and s.tick == 0:
			for id in Data.UPGRADES:  # and spends spare cash on the plant
				if s.money > Data.UPGRADES[id].cost + 600 and s.buy_upgrade(id):
					r.upgrades += 1
		if stage < (stages.size() if late else 4) and s.contracts_done >= stages[stage][0] and s.money >= stages[stage][1]:
			for c in stages[stage][2]:
				s.demolish(Vector2i(c[0], c[1]))
			for bld in stages[stage][3]:
				if not s.build(bld[0], Vector2i(bld[1], bld[2]), bld[3]):
					ok(false, "the bot can afford and place its %s" % bld[0])
				for i in bld[4]:
					s.cycle_raw(Vector2i(bld[1], bld[2]))
			stage += 1
		if care and s.tick == 0:
			for id in s.morale:
				if s.morale[id] < 45.0 and s.money > 300:
					s.answer_raise(id, true)
					r.raises += 1
		s.step()
		r.low = mini(r.low, s.money)
	r.merge({"won": s.won(), "day": s.day, "money": s.money, "contracts": s.contracts_done}, true)
	return r


## Stands in for the gateway: answers every chat with the action in `next`.
class Scripted:
	extends Anansi
	var next := "none"
	var seen := []

	func chat(messages: Array, _npc_id := "", _structured := false) -> Dictionary:
		seen = messages
		return {"source": "gateway", "say": "Right you are, boss.", "action": next, "filtered": false}

	func chat_stream(_messages: Array, on_sentence: Callable, _npc_id := "") -> Dictionary:
		for part in ["Busy day. ", "Bertha held up."]:
			on_sentence.call(part)
		return {"source": "gateway", "say": "Busy day. Bertha held up.", "action": "none", "filtered": false}

	func quest(_w: Dictionary, _s := 3, _t := "", _d := "normal", _so := "", _p := "") -> Dictionary:
		return {"source": "fallback", "quest": null}

	func storyline(_w: Dictionary, _b := 4, _t := "") -> Dictionary:
		return {"source": "fallback", "storyline": null}
