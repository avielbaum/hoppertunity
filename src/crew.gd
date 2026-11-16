## The coworkers' voices: every Anansi call the game makes, and what each answer is allowed to do to the sim.
## The model chooses words and one whitelisted action; sim.gd owns every number. With no gateway, the lines, quests and
## stories in data.gd are used instead and the game plays the same.
class_name Crew
extends Node

var sim: Sim
var api := Anansi.new()
var online := false  # did the gateway answer the last time it was asked (a chat, a remark or a quest)?
var direct_used := false  # has a reply come from the public LLM (no gateway; the GitHub Pages build)?

## Without a gateway, chat asks Pollinations' keyless public LLM directly: one reply per player per minute, checked by the
## SDK only, then the written lines. These are the gateway title's prompt and actions (the Anansi repository's tests keep them
## equal to its gateway config). Quests, stories and end-of-day remarks stay on the written ones.
const DIRECT_PROMPT := "You are a worker at the Hopper Works, a small, friendly gadget factory. The next system message tells you who you are and how the plant is doing. Stay in character, never mention being an AI, and reply in one to three short sentences. Choose exactly one action per reply: morale_up if the manager is kind, fair, encouraging or helps you; morale_down if the manager is rude, dismissive or unfair; offer_quest if the manager asks for work, a task or how to help; share_tip only if the manager asks about upcoming orders or customers; ask_raise only if the manager brings up pay or wages; otherwise none."
const DIRECT_NOTE := "(Reply by Pollinations AI: with no Anansi server, what you type is sent to pollinations.ai.)"
var history := {}  # crew id -> the last few messages, so a coworker remembers the conversation
var queued := {}  # crew id -> a quest generated ahead of time
var stories := {}  # crew id -> four beats (generated at the start of a game, else Data.STORIES)
var told := {}  # crew id -> the gateway's summary of the last quest they gave, so their next one follows on
var _filling := false
var _talking := 0  # conversations waiting for an answer: generation holds off while there are any

## What the gateway is asked for. Measured with qwen3:1.7b: with only the coworker's role as the theme, every quest came
## out as the same errand for nobody in particular, and a storyline as a tour of the plant. These wordings gave "A Favor
## for Sprocket" and a four-beat story about an old mistake and his father.
const QUEST_THEME := "a favour that %s, the %s, asks of the new manager"
const STORY_THEME := ("A personal story about %s, told in four beats: a worry they carry from their past, something that stirs it up, "
		+ "a turning point, and how it is put to rest. Not a tour of the plant. %s")


func setup(s: Sim, url: String, title: String, key: String, player_id: String) -> void:
	sim = s
	add_child(api)
	api.setup(url, title, key, "dev:" + player_id)
	# A small local model on CPU answers one request at a time: 30 s for a first reply was measured, and a reply can
	# also have to wait for a quest that is being generated (20 to 40 s). The SDK's default of 3 s suits a GPU.
	api.timeout_s = 75.0
	api.direct = {"system": DIRECT_PROMPT, "actions": Data.ACTIONS, "timeout_s": 30}  # the service can hold a request while the slot is busy
	for id in Data.CREW:
		history[id] = []
		if not stories.has(id):
			stories[id] = Data.STORIES[id]


## Say `text` to a coworker. Returns {"say", "source", "note", "raise"}: note is what changed in the game ("" if
## nothing), raise is true when they asked for one and the player must answer (sim.answer_raise).
func talk(id: String, text: String) -> Dictionary:
	sim.quest_event("talk_to", id)
	var msgs: Array = [{"role": "system", "content": _brief(id)}] + history[id] + [{"role": "user", "content": text}]
	api.fallback = func(_m): return line(id)
	_talking += 1
	var r: Dictionary = await api.chat(msgs, id, true)
	_talking -= 1
	online = r.source == "gateway"
	history[id] = (history[id] + [{"role": "user", "content": text}, {"role": "assistant", "content": r.say}]).slice(-6)
	var out := {"say": r.say, "source": r.source, "note": "", "raise": false}
	var action: String = r.action if r.action in Data.ACTIONS else "none"
	if action == "offer_quest":
		out.note = offer_quest(id)
	elif action == "ask_raise":
		out.raise = true
	else:
		out.note = sim.apply_action(id, action)
	if r.source == "direct" and not direct_used:  # the first time, say where the words came from and what was sent
		direct_used = true
		out.note = (out.note + " " if out.note != "" else "") + DIRECT_NOTE
	return out


## A coworker's word on the day that just ended, streamed: on_sentence.call(text) runs for each sentence as it arrives
## (with no gateway, once, with a written line). A streamed reply carries no action, so this only ever adds colour.
## It is only streamed when the gateway answered last time: opening a stream to one that is not there can take the
## whole timeout to give up, and a remark is not worth that wait.
func remark(id: String, day_facts: String, on_sentence: Callable) -> Dictionary:
	if not online:
		var text := line(id)
		on_sentence.call(text)
		return {"source": "fallback", "say": text, "action": "none", "filtered": false}
	var msgs: Array = [{"role": "system", "content": _brief(id)}, {"role": "user", "content":
			"The working day is over. " + day_facts + " In one or two short sentences, tell me how the day went from where you stand."}]
	api.fallback = func(_m): return line(id)
	_talking += 1
	var r: Dictionary = await api.chat_stream(msgs, on_sentence, id)
	_talking -= 1
	online = r.source == "gateway"
	return r


## An authored line for this coworker's current mood.
func line(id: String) -> String:
	var pool: Array = Data.LINES[id][sim.mood(id)]
	return pool[sim.rng.randi() % pool.size()]


## Hand the player this coworker's next quest: the generated one if it is queued and valid, else an authored one.
func offer_quest(id: String) -> String:
	if not sim.quest.is_empty():
		return "Finish \"%s\" first." % sim.quest.title
	var q = queued.get(id)
	queued.erase(id)
	if q != null:
		told[id] = str(q.get("story_summary", ""))
	if q == null or not sim.start_quest(q, id):
		var pool: Array = Data.QUESTS[id]
		sim.start_quest(pool[sim.quests_done[id] % pool.size()], id)
	refill()
	return "New quest: %s" % sim.quest.title


## The next storyline beat this coworker tells, or "" if they have nothing new to say yet.
func story_beat(id: String) -> String:
	var n := sim.next_beat(id)
	if n < 0:
		return ""
	sim.tell_beat(id)
	var text: String = stories[id][n]
	if sim.perks.has(id):
		text += "\n[%s]" % Data.CREW[id].perk
	return text


## Generate ahead of time, one request at a time (and none after the first that fails, so a game with no gateway makes
## one request per refill, not eight): a quest for every coworker who has none queued, and at the start of
## a game each coworker's storyline. Generation takes tens of seconds, so it never happens while the player waits.
func refill() -> void:
	if _filling:
		return
	_filling = true
	for id in Data.CREW:
		if not queued.has(id):
			await _quiet()
			var r: Dictionary = await api.quest(_world(), 3, QUEST_THEME % [Data.CREW[id].name, Data.CREW[id].role], "normal",
					(_story_so_far(id) + " " + str(told.get(id, ""))).strip_edges(), Data.PLAYER)
			online = r.quest != null
			if not online:
				break  # the gateway is not answering: stop asking until the next refill
			queued[id] = r.quest
		if sim.beats_told[id] == 0 and stories[id] == Data.STORIES[id]:
			var one := {"npcs": [_npc(id)], "locations": _world().locations, "items": []}
			await _quiet()
			var s: Dictionary = await api.storyline(one, 4, STORY_THEME % [Data.CREW[id].name, Data.CREW[id].persona])
			if s.storyline != null and s.storyline.get("beats") is Array and s.storyline.beats.size() >= 4:
				stories[id] = s.storyline.beats.slice(0, 4).map(func(b): return str(b.get("summary", "")))
	_filling = false


## Wait until nobody is waiting for a coworker to answer: the player's conversation goes before background generation.
func _quiet() -> void:
	while _talking > 0:
		await get_tree().create_timer(0.5).timeout


## Everything a quest may refer to: the coworkers, the kinds of building standing on the floor (all the unlocked kinds
## while it is still empty), and the goods the plant can make. So a quest never sends the player to something they
## would first have to buy, or asks them to ship raw steel.
func _world() -> Dictionary:
	var w := {"npcs": [], "locations": [], "items": []}
	for id in Data.CREW:
		w.npcs.append(_npc(id))
	var built := {}
	for c in sim.cells.values():
		built[c.kind] = true
	for u in sim.unlocked:
		if Data.BUILD.has(u):
			if built.is_empty() or built.has(u):
				w.locations.append({"id": u, "name": Data.BUILD[u].place})
		elif Data.BUILD.values().any(func(b): return b.get("out") == u):
			w.items.append({"id": u, "name": Data.ITEMS[u].name})
	return w


func _npc(id: String) -> Dictionary:
	return {"id": id, "name": Data.CREW[id].name, "role": Data.CREW[id].role}


func _story_so_far(id: String) -> String:
	return " ".join(stories[id].slice(0, sim.beats_told[id]))


## Who the coworker is and how the factory is doing, so what they say fits the game. The rules for choosing an action
## are in the title's system_prefix.
func _brief(id: String) -> String:
	var c: Dictionary = Data.CREW[id]
	var k: Dictionary = sim.contract
	return ("You are %s, the %s at the Hopper Works. %s You are talking to %s. Your morale is %d out of 100 (%s). "
			+ "It is day %d. The plant has %d coins. Current contract: %d %s due by the end of day %d, %d shipped so far. %s") % [
			c.name, c.role, c.persona, Data.PLAYER, int(sim.morale[id]), sim.mood(id), sim.day, sim.money,
			k.qty, Data.ITEMS[k.item].name, k.due, k.done, _story_so_far(id)] + (
			" News at the plant today: " + sim.event.text if sim.event.has("text") else "")
