class_name ItemUI
extends RefCounted
## Presentation helpers for items (data/items.json). Icons: assets/sprites/item_<id>.png (20x20, generated placeholders;
## drop-in PNGs override them); falls back to the item's base "icon" glyph.

static func texture(id: String) -> Texture2D:
	var t := SpriteFactory.png("item_" + id)
	if t != null:
		return t
	return SpriteFactory.get_texture(String(DB.item(id)["icon"]))

static func rarity_color(id: String) -> Color:
	var rc: Dictionary = DB.table("items")["rarity_color"]
	return Color.html(String(rc.get(String(DB.item(id)["rarity"]), "#ffffff")))

static func tooltip(id: String) -> String:
	var d: Dictionary = DB.item(id)
	var tags: Array = d.get("tags", [])
	return "%s  [%s]\n%s%s" % [d["name"], String(d["rarity"]).capitalize(), d["text"], ("\nBuild: " + Arch.tags_text(tags)) if not tags.is_empty() else ""]
