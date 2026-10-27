class_name TipButton
extends Button
## A button whose hover tooltip shows item text with the OSRS skill icons in
## it (see SkillIcons.make_tooltip). Give it an item with show_item() and the
## tooltip is that item's full description (requirements, stats, effects, the
## 'perfect' version), worked out when you hover, so it's never stale; `extra`
## adds lines under it (a price, what a click does).

var item_id := ""
var champ: Champion
var extra := ""


func show_item(id: String, p_champ: Champion = null, p_extra: String = "") -> void:
	item_id = id
	champ = p_champ
	extra = p_extra
	tooltip_text = item_tooltip()


## The item's description plus `extra` ("" without an item).
func item_tooltip() -> String:
	if item_id == "" or not GameData.items.has(item_id):
		return ""
	var t := ItemSlot._tooltip(GameData.item(item_id), champ)
	return t + ("\n\n" + extra if extra != "" else "")


func _get_tooltip(_at_position: Vector2) -> String:
	return item_tooltip() if item_id != "" else tooltip_text


func _make_custom_tooltip(for_text: String) -> Object:
	return SkillIcons.make_tooltip(for_text) if for_text != "" else null
