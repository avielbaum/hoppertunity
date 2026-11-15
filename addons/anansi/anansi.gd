## Anansi game SDK for Godot 4.2+ (GDScript). Same contract as sdk/anansi_client.py and sdk/unity/Anansi.cs:
## ask the gateway, and on a timeout, a 429, an auth error or any failure answer from the fallback so the game never stalls.
## Every call returns a Dictionary with "source" = "gateway" or "fallback". Use it with `await`.
## Tested in Godot 4.3 against a live gateway in CI, from the editor binary and in an exported Linux release build (sdk/godot/test).
##
##   var npc := Anansi.new()
##   add_child(npc)    # it makes HTTP requests as child nodes, so it must be in the scene tree
##   npc.setup("https://gateway.example", "demo", "change-me", platform_token)
##   var r := await npc.chat([{"role": "user", "content": "What do you sell?"}], "shopkeeper", true)
##   print(r.say, " ", r.action)
class_name Anansi
extends Node

## Proof of who the player is, from your platform (on Steam, the hex web-API auth ticket). Tokens expire: refresh yours.
var player_token := ""
## Answers when the gateway cannot: func(messages: Array) -> String. Default is a neutral line.
var fallback := Callable()
## Supply an authored quest/storyline when the gateway cannot: func(world: Dictionary) -> Dictionary (or null).
var quest_fallback := Callable()
var storyline_fallback := Callable()
## Seconds to wait for a plain reply, or for the first sentence of a streamed one.
var timeout_s := 3.0
## Seconds allowed for a whole streamed reply once it has started.
var stream_timeout_s := 30.0
## Quest and storyline generation is slow (tens of seconds on a small GPU): use it on loading screens.
var generation_timeout_s := 60.0

var _base := ""
var _title := ""
var _key := ""


func setup(base_url: String, title_id: String, title_key: String, token := "") -> void:
	_base = base_url.rstrip("/")
	_title = title_id
	_key = title_key
	player_token = token


## One reply: {"source", "say", "action", "filtered"}. With structured = true, "action" is one of the title's
## whitelisted actions, or "none".
func chat(messages: Array, npc_id := "", structured := false) -> Dictionary:
	var body := {"messages": messages, "structured": structured}
	if npc_id != "":
		body["npc_id"] = npc_id
	var r = await _post("/v1/npc", body, timeout_s)
	if r != null and str(r.get("say", "")) != "":  # an empty reply is as good as none
		return {"source": "gateway", "say": str(r["say"]), "action": str(r.get("action", "none")),
				"filtered": bool(r.get("filtered", false))}
	return await _fallback_reply(messages)


## A reply one finished sentence at a time: on_sentence.call(text) runs for each sentence as it arrives.
## If the gateway fails before the first sentence, on_sentence gets the fallback line once. After text was shown,
## that text stands. Returns {"source", "say", "action", "filtered"} when done.
func chat_stream(messages: Array, on_sentence: Callable, npc_id := "") -> Dictionary:
	var body := {"stream": true, "anansi": {"npc_id": npc_id}, "messages": messages}
	var said := ""
	var filtered := false
	var client := HTTPClient.new()
	var started := Time.get_ticks_msec()
	if await _open_stream(client, body, started):
		var buf := PackedByteArray()
		var done := false
		while not done and client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk := client.read_response_body_chunk()
			if chunk.size() == 0:
				var limit := (timeout_s if said == "" else stream_timeout_s) * 1000.0
				if Time.get_ticks_msec() - started > limit:
					break
				await get_tree().process_frame
				continue
			buf.append_array(chunk)
			while true:  # decode whole lines only: a chunk can end in the middle of a multi-byte character
				var nl := buf.find(10)
				if nl < 0:
					break
				var line := buf.slice(0, nl).get_string_from_utf8().strip_edges()
				buf = buf.slice(nl + 1)
				if not line.begins_with("data: {"):
					continue
				if line.begins_with("data: {\"error\""):  # the gateway could not serve the stream
					done = true
					break
				var j = JSON.parse_string(line.substr(6))
				if j is Dictionary and j.get("anansi") is Dictionary and j["anansi"].get("filtered", false):
					filtered = true  # the gateway replaced unsafe text (it says so in the first or last chunk)
				var text := _sentence_of(j)
				if text == "":
					continue
				if said == "":
					started = Time.get_ticks_msec()  # the first sentence arrived: the whole-reply timer starts here
				said += text
				on_sentence.call(text)
	client.close()
	if said != "":
		return {"source": "gateway", "say": said, "action": "none", "filtered": filtered}
	var fb := await _fallback_reply(messages)
	on_sentence.call(fb.say)
	return fb


## One quest that can only use the characters, places and items in `world`:
## {"npcs": [{"id", "name", "role"}], "locations": [...], "items": [...]}.
## Returns {"source", "quest"}; quest is null on fallback unless quest_fallback is set. The reward is a tier
## (small, medium, large): map it to your own loot.
func quest(world: Dictionary, steps := 3, theme := "", difficulty := "normal", story_so_far := "", player := "") -> Dictionary:
	var r = await _post("/v1/quest", _gen_body(world, steps, theme, difficulty, story_so_far, player), generation_timeout_s)
	if r != null and r.get("quest") is Dictionary:
		return {"source": "gateway", "quest": r["quest"]}
	return {"source": "fallback", "quest": quest_fallback.call(world) if quest_fallback.is_valid() else null}


func storyline(world: Dictionary, beats := 4, theme := "") -> Dictionary:
	var r = await _post("/v1/storyline", _gen_body(world, beats, theme, "normal", "", ""), generation_timeout_s)
	if r != null and r.get("storyline") is Dictionary:
		return {"source": "gateway", "storyline": r["storyline"]}
	return {"source": "fallback", "storyline": storyline_fallback.call(world) if storyline_fallback.is_valid() else null}


## The anonymous volunteer-network statistics for `period` ("day", "week" or "all"), or null when the gateway cannot be reached:
## {"period", "published", "min_group", "reporting": {machines, tokens, idle_gpu_pct} or null, "network_tokens", "gpus", "cpus", "systems"}, each row
## {"name", "machines", "tokens", "idle_gpu_pct"}. Nothing is published (published is false, the rest empty) until at least min_group machines
## report, and a smaller group is folded into "Other". The names are hardware names reported by machines: escape them if you show them in markup.
func leaderboard(period := "week", limit := 20) -> Variant:
	var r: Array = await _request(HTTPClient.METHOD_GET, "/v1/leaderboard?period=" + period.uri_encode() + "&limit=" + str(limit), null, timeout_s)
	return r[1] if r[0] == 200 else null


## This player's volunteer credits: {"balance", "pending", "nodes"}, or null when the gateway cannot be reached.
func credits() -> Variant:
	var r: Array = await _request(HTTPClient.METHOD_GET, "/v1/credits", null, timeout_s)
	if r[0] != 200:
		return null
	return {"balance": float(r[1].get("balance", 0)), "pending": float(r[1].get("pending", 0)), "nodes": int(r[1].get("nodes", 0))}


## Link the machine that printed `code` (the node agent's --link, e.g. ABCD-EFGH) to this player.
## {"linked": true, "balance", "pending", "nodes"}, or {"linked": false, "reason": "bad_code" | "unavailable"}.
## Spending is not here: only your game server may spend, with the title's server key.
func link_node(code: String) -> Dictionary:
	var r: Array = await _request(HTTPClient.METHOD_POST, "/v1/credits/link", {"code": code}, timeout_s)
	if r[0] == 200:
		return {"linked": true, "balance": float(r[1].get("balance", 0)), "pending": float(r[1].get("pending", 0)),
				"nodes": int(r[1].get("nodes", 0))}
	return {"linked": false, "reason": "bad_code" if r[0] == 400 or r[0] == 404 else "unavailable"}


func _gen_body(world: Dictionary, count: int, theme: String, difficulty: String, story: String, player: String) -> Dictionary:
	return {"world": world, "steps": count, "theme": theme, "difficulty": difficulty,
			"story_so_far": story, "player": player}


func _headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "X-Anansi-Title: " + _title,
			"X-Anansi-Key: " + _key, "X-Player-Token: " + player_token])


func _fallback_reply(messages: Array) -> Dictionary:
	var say := "..."
	if fallback.is_valid():
		say = str(await fallback.call(messages))
	return {"source": "fallback", "say": say, "action": "none", "filtered": false}


## POST JSON; returns the parsed Dictionary on a 200, otherwise null.
func _post(path: String, body: Dictionary, timeout: float) -> Variant:
	var r: Array = await _request(HTTPClient.METHOD_POST, path, body, timeout)
	return r[1] if r[0] == 200 else null


## [response code, parsed Dictionary or {}]; code 0 when the gateway could not be reached or the body is not an object.
func _request(method: int, path: String, body: Variant, timeout: float) -> Array:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	if req.request(_base + path, _headers(), method, JSON.stringify(body) if body != null else "") != OK:
		req.queue_free()
		return [0, {}]
	var r: Array = await req.request_completed  # [result, response code, headers, body]
	req.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, {}]
	var parsed = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if r[1] == 200 and not parsed is Dictionary:
		return [0, {}]
	return [r[1], parsed if parsed is Dictionary else {}]


## Connects, sends the request and waits for the response headers. True if a 200 stream is ready to read.
func _open_stream(client: HTTPClient, body: Dictionary, started: int) -> bool:
	var u := split_url(_base)
	var tls: bool = u[3]
	if client.connect_to_host(u[0], u[1], TLSOptions.client() if tls else null) != OK:
		return false
	for state in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		while client.get_status() == state:
			client.poll()
			if Time.get_ticks_msec() - started > timeout_s * 1000.0:
				return false
			await get_tree().process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return false
	if client.request(HTTPClient.METHOD_POST, u[2] + "/v1/chat/completions", _headers(), JSON.stringify(body)) != OK:
		return false
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() - started > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return client.has_response() and client.get_response_code() == 200


## [host, port, path prefix, tls] of a base URL. The prefix matters when the gateway sits under a path such as
## https://example.com/anansi; HTTPRequest takes whole URLs, but the streaming HTTPClient needs the parts.
static func split_url(base: String) -> Array:
	var tls := base.begins_with("https://")
	var rest := base.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var prefix := "" if slash < 0 else rest.substr(slash).rstrip("/")
	var port := hostport.get_slice(":", 1).to_int() if ":" in hostport else (443 if tls else 80)
	return [hostport.get_slice(":", 0), port, prefix, tls]


## The text of one parsed streamed chunk, or "".
func _sentence_of(j: Variant) -> String:
	if j is Dictionary and j.get("choices") is Array and j["choices"].size() > 0:
		var delta = j["choices"][0].get("delta")
		if delta is Dictionary:
			return str(delta.get("content", ""))
	return ""
