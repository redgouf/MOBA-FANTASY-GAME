class_name Combat
extends RefCounted
## Pure combat math: the combat triangle, resist mitigation and protection prayers.
## Kept free of scene-tree access so it can be unit tested headless.

enum Style { MELEE, RANGED, MAGIC }
enum Team { SARADOMIN, ZAMORAK, NEUTRAL }

const STYLE_NAMES: Array[String] = ["melee", "ranged", "magic"]
const TEAM_NAMES: Array[String] = ["Saradomin", "Zamorak", "Neutral"]

## Tunables, overwritten from data/rules.json by GameData.
static var tick_seconds := 0.25
static var triangle_bonus := 0.15
static var protect_prayer_reduction := 0.40
static var resist_constant := 100.0
## Game-time clock in seconds, advanced by the match (stops while paused).
static var clock := 0.0


static func configure(rules: Dictionary) -> void:
	tick_seconds = float(rules.get("tick_seconds", tick_seconds))
	triangle_bonus = float(rules.get("triangle_bonus", triangle_bonus))
	protect_prayer_reduction = float(rules.get("protect_prayer_reduction", protect_prayer_reduction))
	resist_constant = float(rules.get("resist_constant", resist_constant))


static func style_from_string(s: String) -> int:
	var idx := STYLE_NAMES.find(s.to_lower())
	return idx if idx >= 0 else Style.MELEE


static func style_name(style: int) -> String:
	return STYLE_NAMES[style] if style >= 0 and style < STYLE_NAMES.size() else "none"


## Melee beats Ranged, Ranged beats Magic, Magic beats Melee.
static func counters(attacker_style: int, defender_style: int) -> bool:
	return (attacker_style == Style.MELEE and defender_style == Style.RANGED) \
		or (attacker_style == Style.RANGED and defender_style == Style.MAGIC) \
		or (attacker_style == Style.MAGIC and defender_style == Style.MELEE)


## Classic diminishing-returns resist curve: 100 resist halves damage.
static func resist_multiplier(resist: float) -> float:
	if resist >= 0.0:
		return resist_constant / (resist_constant + resist)
	# Negative resist amplifies damage, mirroring the positive curve.
	return 2.0 - resist_constant / (resist_constant - resist)


## Converts game ticks into seconds (an OSRS whip is 4 ticks).
static func ticks_to_seconds(ticks: float) -> float:
	return ticks * tick_seconds


## Full mitigation pipeline for one hit.
## protected_style is the defender's active protection prayer, or -1.
static func mitigate(amount: float, damage_style: int, defender_style: int, resist: float,
		armor_pen: float, protected_style: int, ignores_prayer: bool, is_true: bool) -> float:
	if is_true:
		return maxf(amount, 0.0)
	var result := amount
	if counters(damage_style, defender_style):
		result *= 1.0 + triangle_bonus
	result *= resist_multiplier(resist * (1.0 - clampf(armor_pen, 0.0, 1.0)))
	if not ignores_prayer and protected_style == damage_style:
		result *= 1.0 - protect_prayer_reduction
	return maxf(result, 0.0)


## The real OSRS combat level formula, from a build's skill levels.
static func osrs_combat_level(skills: Dictionary) -> int:
	var def := float(skills.get("defence", 1))
	var hp := float(skills.get("hitpoints", 10))
	var pray := floorf(float(skills.get("prayer", 1)) / 2.0)
	var base := 0.25 * (def + hp + pray)
	var melee := 0.325 * (float(skills.get("attack", 1)) + float(skills.get("strength", 1)))
	var ranged := 0.325 * floorf(float(skills.get("ranged", 1)) * 1.5)
	var magic := 0.325 * floorf(float(skills.get("magic", 1)) * 1.5)
	return int(floor(base + maxf(melee, maxf(ranged, magic))))
