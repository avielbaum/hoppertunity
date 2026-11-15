## Every number and every authored word of Hoppertunity. The sim (sim.gd) reads the numbers; crew.gd reads the words
## when the Anansi gateway cannot answer.
class_name Data

const TICKS_PER_DAY := 240  # at 4 ticks a second, one day is a minute at normal speed
const START_MONEY := 600
const RENT := 40
const UPKEEP := 5  # power and parts per machine per day
const MORALE_WEAR := 3.0  # morale every coworker loses on an ordinary day: leave the crew alone and they sour
const BANKRUPT_AT := -500
const WIN_CONTRACTS := 5
const HOPPER_CAP := 20
const INBOUND_INTERVAL := 6.0  # ticks between crates at morale 50

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## buy: price of one crate at the inbound dock (raw materials only). sell: price at the outbound dock.
const ITEMS := {
	"steel": {"name": "steel", "buy": 2, "sell": 1},
	"plastic": {"name": "plastic pellets", "buy": 2, "sell": 1},
	"cardboard": {"name": "cardboard", "buy": 1, "sell": 0},
	"panel": {"name": "steel panels", "sell": 8},
	"casing": {"name": "casings", "sell": 8},
	"gadget": {"name": "gadgets", "sell": 22},
	"boxed": {"name": "boxed gadgets", "sell": 34},
	"copper": {"name": "copper wire", "buy": 3, "sell": 1},
	"coil": {"name": "coils", "sell": 12},
	"smart": {"name": "smart gadgets", "sell": 52},
}

## in/out/time make a kind a machine. crew: whose morale scales it. place: how quests and coworkers call it.
const BUILD := {
	"belt": {"name": "Conveyor", "cost": 5, "place": "the conveyor line", "does": "Carries things one tile along its arrow."},
	"splitter": {"name": "Splitter", "cost": 25, "place": "the splitter", "does": "Sends things ahead, right and left in turn."},
	"hopper": {"name": "Hopper", "cost": 30, "place": "the hoppers", "does": "Holds up to 20 things and feeds them on, so a line can ride out a hiccup."},
	"inbound": {"name": "Inbound dock", "cost": 100, "crew": "dock", "place": "the inbound dock", "does": "Orders raw materials. Click it to change which."},
	"outbound": {"name": "Outbound dock", "cost": 100, "crew": "dock", "place": "the outbound dock", "does": "Sells whatever reaches it."},
	"press": {"name": "Press", "cost": 150, "crew": "tech", "in": {"steel": 1}, "out": "panel", "time": 8.0, "place": "the press"},
	"molder": {"name": "Molder", "cost": 200, "crew": "tech", "in": {"plastic": 1}, "out": "casing", "time": 8.0, "place": "the molder"},
	"assembler": {"name": "Assembler", "cost": 400, "crew": "tech", "in": {"panel": 1, "casing": 1}, "out": "gadget", "time": 12.0, "place": "the assembler"},
	"packer": {"name": "Packer", "cost": 300, "crew": "qa", "in": {"gadget": 1, "cardboard": 1}, "out": "boxed", "time": 6.0, "place": "the packing station"},
	"winder": {"name": "Coil winder", "cost": 350, "crew": "tech", "in": {"copper": 1}, "out": "coil", "time": 10.0, "place": "the coil winder"},
	"fitter": {"name": "Fitter", "cost": 500, "crew": "qa", "in": {"gadget": 1, "coil": 1}, "out": "smart", "time": 10.0, "place": "the fitting station"},
}

## What a new game can build and buy, and what each finished contract adds.
const START_UNLOCKS := ["belt", "splitter", "hopper", "inbound", "outbound", "press", "steel", "panel"]
const UNLOCKS := [["molder", "plastic", "casing"], ["assembler", "gadget"], ["packer", "cardboard", "boxed"],
		["winder", "copper", "coil"], ["fitter", "smart"]]

## Contracts in order. The first five save the plant (WIN_CONTRACTS); the last two are for the third product line, which
## opens up around then. After the list it comes round again, half as big again each time (Sim._contract).
const CONTRACTS := [
	{"item": "panel", "qty": 20, "days": 2, "reward": 200},
	{"item": "casing", "qty": 25, "days": 3, "reward": 350},
	{"item": "gadget", "qty": 20, "days": 3, "reward": 500},
	{"item": "boxed", "qty": 30, "days": 3, "reward": 700},
	{"item": "boxed", "qty": 50, "days": 4, "reward": 1000},
	{"item": "coil", "qty": 30, "days": 3, "reward": 600},
	{"item": "smart", "qty": 25, "days": 4, "reward": 1400},
]

## One-off improvements to buy: somewhere for late-game cash to go. Their effects are in sim.gd (search for the id).
const UPGRADES := {
	"breakroom": {"name": "Break room", "cost": 800, "does": "Everyone loses 1 less morale a day."},
	"crane": {"name": "Dock crane", "cost": 1000, "does": "Inbound docks unload a quarter faster."},
	"tooling": {"name": "Better tooling", "cost": 1200, "does": "Machines work a fifth faster."},
	"scanner": {"name": "Quality scanner", "cost": 1400, "does": "Half as many defective units."},
	"showroom": {"name": "Showroom", "cost": 1600, "does": "Everything sells for a tenth more."},
}

## What can happen on a morning from day 3 on (45% of days). speed: today's multiplier for a coworker's station.
## price: today's multiplier on what things sell for. morale: added to everyone, once. cash: added to the till, once.
## saved_by: if that coworker's morale is 70 or more, nothing bad happens and `saved` is what the player reads.
const EVENT_CHANCE := 0.45
const EVENTS := [
	{"text": "The steel truck is stuck behind a parade. The docks run slow today.", "speed": {"dock": 0.7}, "saved_by": "dock",
		"saved": "A parade blocked the main road, but Dot had the trucks come round the back. No delay."},
	{"text": "The power company is \"looking into it\". Machines run slow today.", "speed": {"tech": 0.75, "qa": 0.75}, "saved_by": "tech",
		"saved": "The power dipped, but Sprocket had the backup generator humming before anyone noticed."},
	{"text": "A safety inspector fines the Works 60 coins for a loose cable.", "cash": -60, "saved_by": "qa",
		"saved": "A safety inspector came by. Tilly's floor was spotless: no fine."},
	{"text": "A buyer sends back a pallet over a scratch. Penny refunds 40 coins.", "cash": -40, "saved_by": "sales",
		"saved": "A buyer grumbled about a scratch, and Penny talked them round. No refund."},
	{"text": "A trade fair is in town. Buyers pay a fifth more today.", "price": 1.2},
	{"text": "The local paper ran a kind piece on the Works. Buyers pay a tenth more today.", "price": 1.1},
	{"text": "It is somebody's birthday and there is cake. Everyone cheers up a little.", "morale": 4.0},
	{"text": "The heating is out and everyone is a bit grumpy.", "morale": -3.0},
]

## The coworkers. perk: what finishing their storyline gives, applied in sim.gd. beat: the buildings they walk between.
const CREW := {
	"dock": {"name": "Dot", "role": "dock supervisor", "wage": 15, "beat": ["inbound", "outbound"],
		"persona": "Dot runs the loading docks. Brisk, dry humour, counts everything twice, hates late trucks.",
		"perk": "Trucks unload faster for good."},
	"tech": {"name": "Sprocket", "role": "machine technician", "wage": 15, "beat": ["press", "molder", "assembler", "winder"],
		"persona": "Sprocket keeps the machines alive. Gentle, tinkers constantly, talks to the machines by name.",
		"perk": "The machines never jam again."},
	"qa": {"name": "Tilly", "role": "packing and quality lead", "wage": 15, "beat": ["packer", "fitter", "outbound"],
		"persona": "Tilly checks every unit that leaves. Exacting, proud of the work, soft spot for a tidy box.",
		"perk": "No more defective units."},
	"sales": {"name": "Penny", "role": "sales rep", "wage": 15, "beat": ["outbound"],
		"persona": "Penny sells what the floor makes. Cheerful, always on the phone, promises a little too much.",
		"perk": "Everything sells for 10% more."},
}

const PLAYER := "Pip Hopper, the new floor manager of the Hopper Works, a small gadget plant on its last chance"

## The only things a conversation can do to the game. The gateway title lists the same names.
const ACTIONS := ["morale_up", "morale_down", "offer_quest", "share_tip", "ask_raise"]
const MORALE_STEP := 5.0
const MORALE_DAILY_CAP := 10.0  # talk can move one coworker this far in one day, either way
const RAISE := 5  # wage per day added by a granted raise
const RAISE_MORALE := 15.0
const REFUSE_MORALE := -10.0

## Quest reward tiers (the model picks the tier, never the numbers).
## boost: full days after today that the giver stays fired up, their station running BOOST times as fast.
const REWARDS := {"small": {"cash": 60, "morale": 5.0, "boost": 0}, "medium": {"cash": 140, "morale": 8.0, "boost": 1},
		"large": {"cash": 280, "morale": 12.0, "boost": 2}}
const BOOST := 1.2
const DELIVER_QTY := {"small": 5, "medium": 10, "large": 15}  # units a "deliver" step asks for

## Spoken when the gateway is unreachable: by coworker, then by mood (low < 35 <= mid < 70 <= high).
const LINES := {
	"dock": {
		"low": ["Two trucks late and nobody tells me anything. Fine. It's fine.", "I'm counting pallets and counting the days, boss."],
		"mid": ["Dock's moving. Keep the belt clear and I'll keep the crates coming.", "Truck's due any minute. They always say that."],
		"high": ["Fastest unload this month. Did you see that? I did. I timed it.", "Good crew, clear bays. This is how a dock should run."],
	},
	"tech": {
		"low": ["Bertha's grinding again and I haven't the parts. She deserves better.", "I can only patch so much with tape, boss."],
		"mid": ["Machines are humming. Mostly in tune.", "Give the press a steady feed and she'll treat you right."],
		"high": ["Listen to that. Not a rattle on the whole floor.", "I oiled everything twice. For fun."],
	},
	"qa": {
		"low": ["I'm passing units I'd have binned last year. It isn't right.", "Nobody notices a good box. Everybody notices a bad one."],
		"mid": ["Corners square, labels straight. That's all I ask.", "Send me gadgets and cardboard and I'll send you something to be proud of."],
		"high": ["Not one return this week. Not one!", "Look at that stack. Like a picture."],
	},
	"sales": {
		"low": ["I keep promising dates and the floor keeps missing them. My phone is not a happy place.", "Customers can hear it in my voice, you know."],
		"mid": ["Orders are steady. Hit the contract and I'll find us a bigger one.", "I told them Friday. Tell me it's Friday."],
		"high": ["They asked for our price list. Asked! I didn't even call.", "Keep shipping like this and I'll sell the building twice."],
	},
}

## Handed out when the gateway cannot make a quest. Same shape as the gateway's quest; steps name things in the world.
const QUESTS := {
	"dock": [
		{"title": "Clear the bay", "summary": "Dot wants proof the outbound side can keep up.", "reward_tier": "small", "steps": [
			{"objective": "inspect", "target_id": "outbound", "description": "Look over the outbound dock with Dot's checklist."},
			{"objective": "deliver", "target_id": "panel", "description": "Ship steel panels without the bay backing up."}]},
		{"title": "The count is off", "summary": "Dot's numbers and the hoppers disagree.", "reward_tier": "medium", "steps": [
			{"objective": "inspect", "target_id": "hopper", "description": "Check what is really sitting in the hoppers."},
			{"objective": "talk_to", "target_id": "tech", "description": "Ask Sprocket whether a sensor is miscounting."},
			{"objective": "talk_to", "target_id": "dock", "description": "Bring the real count back to Dot."}]},
		{"title": "Truck at the gate", "summary": "A driver is early and Dot needs the bay turned round fast.", "reward_tier": "large", "steps": [
			{"objective": "inspect", "target_id": "inbound", "description": "Check the inbound dock is clear for the early truck."},
			{"objective": "deliver", "target_id": "panel", "description": "Get panels out of the door to make room."},
			{"objective": "talk_to", "target_id": "dock", "description": "Tell Dot the bay is turned round."}]},
	],
	"tech": [
		{"title": "Bertha's rattle", "summary": "The press is making a noise Sprocket does not like.", "reward_tier": "small", "steps": [
			{"objective": "inspect", "target_id": "press", "description": "Stand by the press and listen for the rattle."},
			{"objective": "talk_to", "target_id": "tech", "description": "Tell Sprocket what you heard."}]},
		{"title": "A proper test run", "summary": "Sprocket wants the line run hard to prove the repairs.", "reward_tier": "medium", "steps": [
			{"objective": "deliver", "target_id": "panel", "description": "Ship panels from a line running flat out."},
			{"objective": "talk_to", "target_id": "tech", "description": "Report back on how the machines held up."}]},
		{"title": "Spare parts", "summary": "Sprocket needs a part that Dot may have filed under something else.", "reward_tier": "small", "steps": [
			{"objective": "talk_to", "target_id": "dock", "description": "Ask Dot where the last parts delivery went."},
			{"objective": "inspect", "target_id": "hopper", "description": "Look in the hoppers: that is where it ended up."},
			{"objective": "talk_to", "target_id": "tech", "description": "Bring Sprocket the part."}]},
	],
	"qa": [
		{"title": "Spot check", "summary": "Tilly wants the boss to see what quality means.", "reward_tier": "small", "steps": [
			{"objective": "inspect", "target_id": "outbound", "description": "Watch the units leaving at the outbound dock."},
			{"objective": "talk_to", "target_id": "qa", "description": "Tell Tilly what you saw."}]},
		{"title": "A perfect batch", "summary": "Tilly wants one batch she can sign her name to.", "reward_tier": "medium", "steps": [
			{"objective": "deliver", "target_id": "panel", "description": "Ship a clean batch of panels."},
			{"objective": "talk_to", "target_id": "qa", "description": "Let Tilly sign off the batch."}]},
		{"title": "The wobble", "summary": "Tilly thinks a conveyor is shaking units out of true.", "reward_tier": "small", "steps": [
			{"objective": "inspect", "target_id": "belt", "description": "Watch the conveyor line for a wobble."},
			{"objective": "talk_to", "target_id": "tech", "description": "Ask Sprocket to steady it."},
			{"objective": "talk_to", "target_id": "qa", "description": "Tell Tilly it is fixed."}]},
	],
	"sales": [
		{"title": "A sample for the client", "summary": "Penny promised a client a look at the goods.", "reward_tier": "small", "steps": [
			{"objective": "deliver", "target_id": "panel", "description": "Ship a sample lot of panels."},
			{"objective": "talk_to", "target_id": "sales", "description": "Tell Penny the samples are on the truck."}]},
		{"title": "The site visit", "summary": "A buyer is coming and Penny wants the floor ready.", "reward_tier": "medium", "steps": [
			{"objective": "talk_to", "target_id": "dock", "description": "Ask Dot to keep a bay free for the visitor."},
			{"objective": "inspect", "target_id": "inbound", "description": "Make sure the inbound dock looks the part."},
			{"objective": "talk_to", "target_id": "sales", "description": "Tell Penny the floor is ready."}]},
		{"title": "Proof of quality", "summary": "A buyer doubts the Works. Penny wants Tilly's word and the goods to back it.", "reward_tier": "large", "steps": [
			{"objective": "talk_to", "target_id": "qa", "description": "Ask Tilly to vouch for this week's units."},
			{"objective": "deliver", "target_id": "panel", "description": "Ship a batch the buyer can inspect."},
			{"objective": "talk_to", "target_id": "sales", "description": "Give Penny the good news."}]},
	],
}

## Each coworker's story when the gateway cannot write one: four beats, told one at a time as you finish their quests.
const STORIES := {
	"dock": ["Dot counts everything twice because of the day a whole truck went missing on her watch, years ago.",
		"The missing truck was never found. Dot still keeps its paperwork in her locker.",
		"A driver mentions an old Hopper Works trailer rusting in a yard two towns over. Dot goes very quiet.",
		"Dot brings the trailer home. The count finally balances, and she tears up the old paperwork."],
	"tech": ["Sprocket named the old press Bertha after the engineer who trained him and never got her name on anything.",
		"Bertha's maintenance log has notes in two hands. Sprocket keeps writing in the margins as if she will answer.",
		"The real Bertha, long retired, sends a postcard: she heard the Works was still running. Sprocket reads it to the press.",
		"Bertha visits. She listens to the press for a minute, nods once, and Sprocket stops worrying for the first time in years."],
	"qa": ["Tilly once let a bad batch through on a rushed Friday, and has checked every single unit since.",
		"A customer writes to say a Hopper gadget from that Friday batch still works. Tilly does not believe it.",
		"She asks for the unit back, tests it for a week, and cannot make it fail.",
		"Tilly frames the letter by the packing station and, for once, lets a box go out without opening it twice."],
	"sales": ["Penny promises a little too much because the last rep promised nothing and the order book went empty.",
		"She admits the biggest client only stays out of habit and is shopping around.",
		"Penny wants to stop promising and start showing: she invites the client to walk the floor.",
		"The client signs for three years. Penny writes a delivery date on the board and, for once, pads it."],
}
