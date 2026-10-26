class_name TipButton
extends Button
## A button whose hover tooltip shows item text with the OSRS skill icons in
## it (see SkillIcons.make_tooltip).


func _make_custom_tooltip(for_text: String) -> Object:
	return SkillIcons.make_tooltip(for_text)
