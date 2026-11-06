class_name Arch
extends RefCounted
## Archetypes (data/archetypes.json): tags on cards / items, synergy counting, display helpers.

static func table() -> Dictionary:
	return DB.table("archetypes")["archetypes"]

static func ids() -> Array:
	return table().keys()

static func name_of(tag: String) -> String:
	return String(table().get(tag, {}).get("name", tag))

static func short_of(tag: String) -> String:
	return String(table().get(tag, {}).get("short", tag.left(3).to_upper()))

static func color_of(tag: String) -> Color:
	return Color.html(String(table().get(tag, {}).get("color", "#ffffff")))

static func tags_text(tags: Array) -> String:
	var p: Array = []
	for t in tags:
		p.append(name_of(String(t)))
	return " / ".join(p)

static func threshold() -> int:
	return int(DB.table("archetypes").get("synergy_threshold", 3))

## tag -> weight of your current build: deck cards 1 each, items 2 each.
static func counts(deck: Array, items: Array) -> Dictionary:
	var d := {}
	for id in deck:
		for t in DB.card(String(id)).get("tags", []):
			d[t] = int(d.get(t, 0)) + 1
	for id in items:
		for t in DB.item(String(id)).get("tags", []):
			d[t] = int(d.get(t, 0)) + 2
	return d

## Tags of `tags` that your build already leans into (count >= threshold): the "synergy" highlight.
static func matching(tags: Array, deck: Array, items: Array) -> Array:
	var c := counts(deck, items)
	var out: Array = []
	for t in tags:
		if int(c.get(t, 0)) >= threshold():
			out.append(t)
	return out

## The archetype your build leans into most ("" if nothing reaches the threshold).
static func main_tag(deck: Array, items: Array) -> String:
	var c := counts(deck, items)
	var best := ""
	var bn := threshold() - 1
	for t in c:
		if int(c[t]) > bn:
			bn = int(c[t])
			best = String(t)
	return best
