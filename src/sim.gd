## The whole game as plain data on a fixed tick. No nodes and no rendering, so it runs headless in test/checks.gd and
## saves as one Dictionary. main.gd draws it; crew.gd feeds conversations and quests into it.
class_name Sim
extends RefCounted

signal sold(pos: Vector2i, item: String, amount: int)
signal day_ended(summary: Dictionary)
signal contract_changed(finished: bool)
signal quest_changed(finished: bool)

var money := Data.START_MONEY
var day := 1
var tick := 0   # within the day
var ticks := 0  # since the game began
var floor_size := Vector2i(16, 12)
var cells := {}  # Vector2i -> {"kind", "dir", ...state}
var morale := {}
var wages := {}
var talk_moved := {}  # crew id -> morale moved by talk today, for the daily cap
var unlocked: Array = Data.START_UNLOCKS.duplicate()
var contract := {}
var contracts_done := 0
var offers := []  # after a contract ends: the contracts Penny can get. The first is taken unless choose() picks another
var history := []  # one entry per finished day: {"day", "net", "morale"}
var upgrades: Array = []  # ids from Data.UPGRADES that have been bought
var event := {}  # today's event from Data.EVENTS, {} on a quiet day
var contract_revealed := false  # a tip showed the player the next contract
var quest := {}  # the active quest: the gateway's shape plus "giver", "step", "have", "need"
var quests_done := {}  # crew id -> finished quests, which paces their storyline
var beats_told := {}  # crew id -> storyline beats already told
var perks := {}  # crew id -> true once their storyline is finished
var boosts := {}  # crew id -> day-ends left of being fired up after an errand (see Data.REWARDS)
var last_reward := {}  # what the last finished quest gave: {"giver", "cash", "morale", "boost"}
var walkout := false
var today := {"revenue": 0, "costs": 0, "built": 0, "shipped": 0, "defects": 0}
var rng := RandomNumberGenerator.new()
var _done := {}  # belts already resolved this tick


func _init(rng_seed := 1) -> void:
	rng.seed = rng_seed
	for id in Data.CREW:
		morale[id] = 50.0
		wages[id] = Data.CREW[id].wage
		talk_moved[id] = 0.0
		quests_done[id] = 0
		beats_told[id] = 0
	contract = _contract(0)


# ---------- building ----------

func can_build(kind: String, pos: Vector2i) -> bool:
	return kind in unlocked and not cells.has(pos) and Rect2i(Vector2i.ZERO, floor_size).has_point(pos) \
			and money >= Data.BUILD[kind].cost


func build(kind: String, pos: Vector2i, dir := 0) -> bool:
	if not can_build(kind, pos):
		return false
	money -= Data.BUILD[kind].cost
	today.built += Data.BUILD[kind].cost  # kept apart from running costs, so a day's profit says how the line is doing
	var c := {"kind": kind, "dir": dir}
	match kind:
		"belt", "splitter":
			c.merge({"item": "", "from": pos, "at": 0, "turn": 0})
		"hopper":
			c["store"] = []
		"inbound":
			c.merge({"raw": "steel", "t": 0.0})
		"outbound":
			pass
		_:
			c.merge({"buf": {}, "busy": false, "prog": 0.0, "out": "", "jam": 0})
	cells[pos] = c
	return true


## The line a new game opens on, free of charge: steel in, one press, panels out. The tutorial builds on it.
func starter() -> void:
	var line := ["inbound", "belt", "press", "belt", "belt", "outbound"]
	for i in line.size():
		money += Data.BUILD[line[i]].cost
		build(line[i], Vector2i(4 + i, 4), 0)
	today.built = 0


## Remove a building for half its cost back. Whatever it held is lost.
func demolish(pos: Vector2i) -> void:
	if cells.has(pos):
		money += Data.BUILD[cells[pos].kind].cost / 2
		cells.erase(pos)


func rotate(pos: Vector2i) -> void:
	if cells.has(pos):
		cells[pos].dir = (cells[pos].dir + 1) % 4


## The raw materials an inbound dock can order, and switching a dock to the next one.
func raws() -> Array:
	return unlocked.filter(func(u): return Data.ITEMS.has(u) and Data.ITEMS[u].has("buy"))


func cycle_raw(pos: Vector2i) -> void:
	var c = cells.get(pos)
	if c != null and c.kind == "inbound":
		var r := raws()
		c.raw = r[(r.find(c.raw) + 1) % r.size()]


func expand_cost() -> int:
	return 150 * (floor_size.x - 14) / 2


func expand() -> bool:
	if money < expand_cost() or floor_size.x >= 28:
		return false
	money -= expand_cost()
	today.built += expand_cost()
	floor_size += Vector2i(2, 2)
	return true


# ---------- morale ----------

## How fast a coworker's station runs: 0.8 at morale 0, 1.2 at 100.
func mult(crew: String) -> float:
	return (0.8 + 0.4 * morale[crew] / 100.0) * float(event.get("speed", {}).get(crew, 1.0)) \
			* (Data.BOOST if boosts.get(crew, 0) > 0 else 1.0)


func team_morale() -> float:
	var s := 0.0
	for id in morale:
		s += morale[id]
	return s / morale.size()


func add_morale(crew: String, d: float) -> void:
	morale[crew] = clampf(morale[crew] + d, 0.0, 100.0)


func mood(crew: String) -> String:
	return "low" if morale[crew] < 35.0 else ("mid" if morale[crew] < 70.0 else "high")


## What a conversation is allowed to do. Returns a short note for the player, or "" if nothing changed.
## offer_quest and ask_raise are decisions for the player, so crew.gd and the UI handle those.
func apply_action(crew: String, action: String) -> String:
	match action:
		"morale_up", "morale_down":
			var want := Data.MORALE_STEP if action == "morale_up" else -Data.MORALE_STEP
			var room := Data.MORALE_DAILY_CAP - absf(talk_moved[crew])
			if room <= 0.0:
				return ""
			var d := clampf(want, -room, room)
			talk_moved[crew] += d
			add_morale(crew, d)
			return "%s's morale %s." % [Data.CREW[crew].name, "rises" if d > 0 else "drops"]
		"share_tip":
			if contract_revealed:
				return ""
			contract_revealed = true
			var n: Dictionary = _contract(contracts_done + 1)
			return "Tip: the next contract will be %d %s." % [n.qty, Data.ITEMS[n.item].name]
	return ""


func answer_raise(crew: String, grant: bool) -> void:
	if grant:
		wages[crew] += Data.RAISE
	add_morale(crew, Data.RAISE_MORALE if grant else Data.REFUSE_MORALE)


# ---------- contracts ----------

func _contract(n: int) -> Dictionary:
	var base: Dictionary = Data.CONTRACTS[n % Data.CONTRACTS.size()]
	var more := 1.0 + 0.5 * (n / Data.CONTRACTS.size())  # past the list it comes round again, half as big again each time
	return {"item": base.item, "qty": int(base.qty * more), "done": 0, "due": day + base.days - 1, "reward": int(base.reward * more)}


## The contracts on offer for the n-th deal. Penny's mood decides how many customers she can line up: sour, only the
## standard one; fine, also a rush job (less to ship, less time, less pay); happy, also a bulk order (more of each).
func _offers(n: int) -> Array:
	var std := _contract(n)
	std["label"] = "Standard"
	var out := [std]
	if morale.sales >= 35.0:
		var rush := std.duplicate()
		rush.merge({"label": "Rush", "qty": int(ceil(std.qty * 0.75)), "due": maxi(day, std.due - 1), "reward": int(std.reward * 0.7)}, true)
		out.append(rush)
	if morale.sales >= 60.0:
		var bulk := std.duplicate()
		bulk.merge({"label": "Bulk", "qty": int(std.qty * 1.8), "due": std.due + 1, "reward": std.reward * 2}, true)
		out.append(bulk)
	return out


func choose(i: int) -> void:
	if i >= 0 and i < offers.size():
		contract = offers[i]
		offers = []
		contract_changed.emit(false)


func buy_upgrade(id: String) -> bool:
	if id in upgrades or not Data.UPGRADES.has(id) or money < Data.UPGRADES[id].cost:
		return false
	money -= Data.UPGRADES[id].cost
	today.built += Data.UPGRADES[id].cost
	upgrades.append(id)
	return true


## What an event from Data.EVENTS comes to today: its one-off effects are applied now, and what is returned lasts the
## day. A coworker in good spirits heads their kind of trouble off, and then only the story of it is left.
func settle_event(e: Dictionary) -> Dictionary:
	if e.has("saved_by") and morale[e.saved_by] >= 70.0:
		return {"text": e.saved}
	for id in morale:
		add_morale(id, e.get("morale", 0.0))
	money += e.get("cash", 0)
	today.costs -= e.get("cash", 0)
	return e.duplicate(true)


func won() -> bool:
	return contracts_done >= Data.WIN_CONTRACTS


func bankrupt() -> bool:
	return money < Data.BANKRUPT_AT


func _finish_contract() -> void:
	var pay := int(round(contract.reward * _price_mult()))
	money += pay
	today.revenue += pay
	if contracts_done < Data.UNLOCKS.size():
		for u in Data.UNLOCKS[contracts_done]:
			if not u in unlocked:
				unlocked.append(u)
	contracts_done += 1
	contract_revealed = false
	add_morale("sales", 5.0)
	offers = _offers(contracts_done)
	contract = offers[0]
	contract_changed.emit(true)


# ---------- quests and storylines ----------

## Start a quest (from the gateway or from Data.QUESTS). False if it names something this game does not have.
func start_quest(q: Dictionary, giver: String) -> bool:
	if not q.get("steps") is Array or q.steps.is_empty():
		return false
	for s in q.steps:
		var pool: Dictionary = {"talk_to": Data.CREW, "inspect": Data.BUILD, "deliver": Data.ITEMS}.get(s.get("objective"), {})
		if not pool.has(s.get("target_id")):
			return false
	if not Data.REWARDS.has(q.get("reward_tier")):
		q["reward_tier"] = "small"
	quest = q.duplicate(true)
	quest.merge({"giver": giver, "step": 0, "have": 0})
	_arm_step()
	quest_changed.emit(false)
	return true


func _arm_step() -> void:
	quest.have = 0
	quest["need"] = Data.DELIVER_QTY[quest.reward_tier] if quest.steps[quest.step].objective == "deliver" else 1


## Something the player did: talked to a coworker, looked at a station, shipped an item.
func quest_event(objective: String, target: String) -> void:
	if quest.is_empty():
		return
	var s: Dictionary = quest.steps[quest.step]
	if s.objective != objective or s.target_id != target:
		return
	quest.have += 1
	if quest.have < quest.need:
		return
	quest.step += 1
	if quest.step < quest.steps.size():
		_arm_step()
		quest_changed.emit(false)
		return
	var r: Dictionary = Data.REWARDS[quest.reward_tier]
	money += r.cash
	today.revenue += r.cash
	add_morale(quest.giver, r.morale)
	quests_done[quest.giver] += 1
	if r.boost > 0:
		boosts[quest.giver] = maxi(boosts.get(quest.giver, 0), r.boost + 1)  # the rest of today, and r.boost days more
	last_reward = {"giver": quest.giver, "cash": r.cash, "morale": r.morale, "boost": r.boost}
	quest = {}
	quest_changed.emit(true)


## The next storyline beat this coworker is ready to tell (0-based), or -1. One beat per finished quest of theirs,
## and nobody opens up while miserable.
func next_beat(crew: String) -> int:
	var n: int = beats_told[crew]
	return n if n < 4 and n <= quests_done[crew] and morale[crew] >= 40.0 else -1


func tell_beat(crew: String) -> void:
	beats_told[crew] += 1
	add_morale(crew, 3.0)
	if beats_told[crew] >= 4:
		perks[crew] = true


# ---------- the tick ----------

func step() -> void:
	ticks += 1
	if not walkout:
		_done = {}
		for pos in cells:
			var c: Dictionary = cells[pos]
			match c.kind:
				"belt", "splitter":
					_advance(pos)
				"hopper":
					if not c.store.is_empty() and _push(pos, c.dir, c.store[0]):
						c.store.pop_front()
				"inbound":
					_inbound(pos, c)
				"outbound":
					pass
				_:
					_machine(pos, c)
	tick += 1
	if tick >= Data.TICKS_PER_DAY:
		_end_day()


func _inbound(pos: Vector2i, c: Dictionary) -> void:
	c.t += mult("dock") * (1.25 if perks.has("dock") else 1.0) * (1.25 if "crane" in upgrades else 1.0)
	var price: int = Data.ITEMS[c.raw].buy
	if c.t >= Data.INBOUND_INTERVAL and money >= price and _push(pos, c.dir, c.raw):
		c.t = 0.0
		money -= price
		today.costs += price


func _machine(pos: Vector2i, c: Dictionary) -> void:
	var b: Dictionary = Data.BUILD[c.kind]
	if c.out != "" and _push(pos, c.dir, c.out):
		c.out = ""
	if c.out != "":  # nowhere to put the finished unit: wait
		return
	if c.jam > 0:
		c.jam -= 1
	elif c.busy:
		c.prog += mult(b.crew) * (1.2 if "tooling" in upgrades else 1.0)
		if c.prog >= b.time:
			c.merge({"busy": false, "prog": 0.0}, true)
			if not _push(pos, c.dir, b.out):
				c.out = b.out
		elif morale.tech < 30.0 and not perks.has("tech") and rng.randf() < 0.01:
			c.jam = 20  # an unhappy technician means machines jam now and then
	else:
		for item in b["in"]:
			if c.buf.get(item, 0) < b["in"][item]:
				return
		for item in b["in"]:
			c.buf[item] -= b["in"][item]
		c.busy = true


## A belt hands its item on. The belt ahead is resolved first, so a full line moves as one.
func _advance(pos: Vector2i) -> void:
	if _done.has(pos):  # also stops a ring of belts from recursing forever
		return
	_done[pos] = true
	var c: Dictionary = cells[pos]
	if c.item == "" or c.at >= ticks:
		return
	if c.kind == "belt":
		if _push(pos, c.dir, c.item):
			c.item = ""
		return
	for i in 3:  # splitter: ahead, right, left, starting one further each time something leaves
		var d: int = (c.dir + [0, 1, 3][(c.turn + i) % 3]) % 4
		if _push(pos, d, c.item):
			c.item = ""
			c.turn = (c.turn + i + 1) % 3
			return


## Try to hand `item` from the building at `pos` to its neighbour in direction `dir`.
func _push(pos: Vector2i, dir: int, item: String) -> bool:
	var to: Vector2i = pos + Data.DIRS[dir]
	var t = cells.get(to)
	if t == null:
		return false
	match t.kind:
		"belt", "splitter":
			if to + Data.DIRS[t.dir] == pos:  # it points back at us
				return false
			_advance(to)
			if t.item != "":
				return false
			t.merge({"item": item, "from": pos, "at": ticks}, true)
		"hopper":
			if t.store.size() >= Data.HOPPER_CAP:
				return false
			t.store.append(item)
		"outbound":
			_sell(to, item)
		"inbound":
			return false
		_:
			var need: Dictionary = Data.BUILD[t.kind]["in"]
			if not need.has(item) or t.buf.get(item, 0) >= 2 * need[item]:
				return false
			t.buf[item] = t.buf.get(item, 0) + 1
	return true


func _price_mult() -> float:
	return mult("sales") * (1.1 if perks.has("sales") else 1.0) * (1.1 if team_morale() > 70.0 else 1.0) \
			* (1.1 if "showroom" in upgrades else 1.0) * float(event.get("price", 1.0))


func _sell(pos: Vector2i, item: String) -> void:
	# an unhappy quality lead lets bad units through: they come back, unpaid and uncounted
	if Data.BUILD.values().any(func(b): return b.get("out") == item) and not perks.has("qa") \
			and rng.randf() < 0.15 * (1.0 - morale.qa / 100.0) * (0.5 if "scanner" in upgrades else 1.0):
		today.defects += 1
		sold.emit(pos, item, 0)
		return
	var pay := int(round(Data.ITEMS[item].sell * _price_mult()))
	money += pay
	today.revenue += pay
	today.shipped += 1
	sold.emit(pos, item, pay)
	quest_event("deliver", item)
	if item == contract.item:
		contract.done += 1
		if contract.done >= contract.qty:
			_finish_contract()
		else:
			contract_changed.emit(false)


func _end_day() -> void:
	var pay := Data.RENT
	for id in wages:
		pay += wages[id]
	for c in cells.values():
		if Data.BUILD[c.kind].has("in"):
			pay += Data.UPKEEP
	money -= pay
	today.costs += pay
	history.append({"day": day, "net": today.revenue - today.costs, "morale": int(team_morale())})
	var summary := today.duplicate()
	summary.merge({"day": day, "wages_rent": pay, "walkout": walkout, "missed": false})
	for id in morale:
		# a day off clears the air; a normal day wears a little
		add_morale(id, 8.0 if walkout else -(Data.MORALE_WEAR - (1.0 if "breakroom" in upgrades else 0.0)))
		talk_moved[id] = 0.0
	day += 1
	tick = 0
	if day > contract.due:  # missed the deadline: the customer walks, and Penny has to make the call
		summary.missed = true
		money -= contract.reward / 4
		add_morale("sales", -8.0)
		contract_revealed = false
		offers = _offers(contracts_done)
		contract = offers[0]
		contract_changed.emit(false)
	for id in boosts.keys():
		boosts[id] -= 1
		if boosts[id] <= 0:
			boosts.erase(id)
	event = {}
	if day >= 3 and rng.randf() < Data.EVENT_CHANCE:
		event = settle_event(Data.EVENTS[rng.randi() % Data.EVENTS.size()])
	summary["event"] = event.get("text", "")
	walkout = team_morale() < 30.0
	summary["walkout_next"] = walkout
	today = {"revenue": 0, "costs": 0, "built": 0, "shipped": 0, "defects": 0}
	day_ended.emit(summary)


# ---------- saving ----------

const _SAVED := ["money", "day", "tick", "ticks", "morale", "wages", "talk_moved", "unlocked", "contract", "contracts_done",
		"contract_revealed", "offers", "history", "upgrades", "event", "quest", "quests_done", "beats_told", "perks", "boosts", "walkout", "today"]


func save() -> Dictionary:
	var d := {"floor": [floor_size.x, floor_size.y], "cells": []}
	for k in _SAVED:
		var v = get(k)
		d[k] = v.duplicate(true) if v is Dictionary or v is Array else v  # a copy: the caller may keep or change it
	for pos in cells:
		var c: Dictionary = cells[pos].duplicate(true)
		c.merge({"x": pos.x, "y": pos.y}, true)
		if c.has("from"):
			c.from = [c.from.x, c.from.y]
		d.cells.append(c)
	return d


## Load what save() made (after a round trip through JSON, which turns every number into a float).
func restore(d: Dictionary) -> void:
	for k in _SAVED:
		if d.has(k):
			set(k, _ints(d[k]) if k not in ["morale", "talk_moved"] else d[k])
	today.merge({"revenue": 0, "costs": 0, "built": 0, "shipped": 0, "defects": 0})  # a save from before a field existed
	floor_size = Vector2i(int(d.floor[0]), int(d.floor[1]))
	cells = {}
	for saved in d.cells:
		var c: Dictionary = _ints(saved)
		for k in ["t", "prog"]:
			if c.has(k):
				c[k] = float(c[k])
		if c.has("from"):
			c.from = Vector2i(c.from[0], c.from[1])
		var pos := Vector2i(c.x, c.y)
		c.erase("x")
		c.erase("y")
		cells[pos] = c


static func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		return v.map(_ints)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	return v
