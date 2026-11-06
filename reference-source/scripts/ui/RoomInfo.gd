class_name RoomInfo
extends RefCounted
## Shared presentation constants for room types.
const TYPE_ICON := {"battle": "icon_claw", "elite": "icon_skull", "boss": "icon_skull", "event": "icon_question", "forage": "icon_meat", "puzzle": "icon_bolt", "cave": "icon_eye"}
const TYPE_COLOR := {"battle": "#c85a4a", "elite": "#e0802a", "boss": "#b03ad0", "event": "#e0d060", "forage": "#6fc24e", "puzzle": "#6fa8e8", "cave": "#9a7aff"}
const TYPE_NAME := {"battle": "Battle", "elite": "ELITE Battle", "boss": "BOSS", "event": "Event", "forage": "Foraging", "puzzle": "Puzzle", "cave": "SECRET CAVE"}

## What an exit gate shows BEFORE you open it (like Hades): the reward, never the encounter.
const REWARD_HINT := {
	"battle": {"icon": "icon_deck", "label": "Cards & XP", "color": "#d8b45a"},
	"elite": {"icon": "icon_bolt", "label": "Rare cards & big XP", "color": "#e8802a"},
	"puzzle": {"icon": "icon_heart", "label": "XP, food & healing", "color": "#6fa8e8"},
	"forage": {"icon": "icon_meat", "label": "Food", "color": "#6fc24e"},
	"event": {"icon": "icon_question", "label": "Unknown boon or risk", "color": "#e0d060"},
	"boss": {"icon": "icon_skull", "label": "BOSS lair", "color": "#c040e0"},
	"cave": {"icon": "icon_eye", "label": "Secret cave: spiders & unique loot", "color": "#9a7aff"},
}

static func reward_hint(type: String) -> Dictionary:
	return REWARD_HINT.get(type, REWARD_HINT["event"])
