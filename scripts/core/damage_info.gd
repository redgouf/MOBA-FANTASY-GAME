class_name DamageInfo
extends RefCounted
## One hit of damage travelling from a source to a target.

var amount := 0.0
var style: int = Combat.Style.MELEE
var source: Node = null          # the Unit that dealt it (may be freed later)
var is_attack := false           # auto attack (triggers on-hit effects)
var is_ability := false
var is_true := false             # ignores resists, triangle and prayer
var ignores_prayer := false
var ignore_triangle := false     # e.g. turret shots on minions (fixed % of max health)
var armor_pen := 0.0
var crit_mult := 1.0
var label := ""


static func make(p_amount: float, p_style: int, p_source: Node) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.style = p_style
	info.source = p_source
	return info
