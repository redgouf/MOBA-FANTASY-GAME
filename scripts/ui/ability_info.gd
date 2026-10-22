class_name AbilityInfo
extends RefCounted
## Tooltip maths for abilities: how much each damage (or heal) effect does right
## now, split into what the spell gives at its rank, what the champion's own
## stats add and what items add, then the combined total.

const RATIO_NAMES := {"damage": "damage", "magic_power": "magic power", "skill_power": "skill power"}


## One entry per damage/heal effect:
## {kind, spell, stats, items, per_hit, hits, ticks, total, ratio_text, extra}
static func breakdown(c: Champion, ab: Dictionary, rank: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx := {"rank": maxi(rank, 1)}
	for e in ab.get("effects", []):
		var kind := str(e.get("type", ""))
		if kind != "damage" and kind != "heal":
			continue
		var spell := AbilityRunner.flat_amount(c, e, ctx)
		var stats := 0.0
		var items := 0.0
		var ratio_parts: Array[String] = []
		var ratio: Dictionary = e.get("ratio", {})
		for key in ratio:
			var r := float(ratio[key])
			var split := stat_split(c, str(key))
			stats += r * split.x
			items += r * split.y
			ratio_parts.append("%d%% %s" % [int(round(r * 100.0)), RATIO_NAMES.get(key, str(key))])
		var hits := maxi(1, int(e.get("hits", 1)))
		var ticks := maxi(1, int(e.get("repeat", 1)))
		var per_hit := spell + stats + items
		var extra: Array[String] = []
		if e.has("pct_max_health"):
			extra.append("+%s%% of the target's max health" % _pct(float(e["pct_max_health"])))
		if e.has("pct_current_health"):
			extra.append("+%s%% of the target's current health" % _pct(float(e["pct_current_health"])))
		if e.has("pct_missing"):
			extra.append("+%s%% of missing health" % _pct(float(e["pct_missing"])))
		if e.has("pct_max") and kind == "heal":
			extra.append("+%s%% of max health" % _pct(float(e["pct_max"])))
		if e.has("missing_health_bonus"):
			extra.append("up to +%s%% more as your health drops" % _pct(float(e["missing_health_bonus"])))
		if e.has("bonus_below_health"):
			var low: Dictionary = e["bonus_below_health"]
			extra.append("x%.1f on targets below %d%% health" % [float(low.get("mult", 1.5)), int(float(low.get("threshold", 0.3)) * 100.0)])
		if bool(e.get("cascade", false)):
			extra.append("missed hits roll into the next one")
		if spell <= 0.0 and stats + items <= 0.0 and extra.is_empty():
			continue
		out.append({"kind": kind, "spell": spell, "stats": stats, "items": items, "per_hit": per_hit,
			"hits": hits, "ticks": ticks, "total": per_hit * hits * ticks,
			"ratio_text": ", ".join(ratio_parts), "extra": extra})
	return out


## (from the champion's own stats, from items) for a ratio stat.
static func stat_split(c: Champion, key: String) -> Vector2:
	match key:
		"damage":
			var item := c._item_stat("damage")
			return Vector2(c.get_damage() - item, item)
		"magic_power":
			var item := c._item_stat("magic_power")
			return Vector2(c.get_magic_power() - item, item)
		"skill_power":
			var mult := maxf(0.0, 1.0 + c.status_sum("skill_power_mult"))
			var item := c._item_stat("skill_power") * mult
			return Vector2(c.get_skill_power() - item, item)
	return Vector2.ZERO


static func _pct(x: float) -> String:
	var v := x * 100.0
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v


## Tooltip lines for an ability (kit slot or item spec) as `c` has it now.
static func tooltip(c: Champion, key: String) -> String:
	var ab := c.get_action(key)
	var rank := c.ability_rank(key)
	var is_item := key.begins_with("item:")
	var lines: Array[String] = []
	if is_item:
		lines.append(str(ab.get("name", "")))
	else:
		lines.append("%s  (rank %d/%d)" % [ab.get("name", ""), rank, c.max_rank(key)])
	lines.append(str(ab.get("text", "")))
	var rows := breakdown(c, ab, rank)
	for row in rows:
		var heal: bool = row["kind"] == "heal"
		lines.append("")
		var head := "Healing" if heal else "Damage"
		if not is_item and rank <= 0:
			head += " at rank 1"
		lines.append(head + ":")
		lines.append("  Spell%s: %d" % ["" if is_item else " (rank %d)" % maxi(rank, 1), roundi(row["spell"])])
		if str(row["ratio_text"]) != "":
			lines.append("  Your stats: +%d" % roundi(row["stats"]))
			lines.append("  Items: +%d" % roundi(row["items"]))
			lines.append("  (scales with %s)" % row["ratio_text"])
		var total := "  Total: %d" % roundi(row["per_hit"])
		if int(row["hits"]) > 1:
			total += " per hit, x%d hits = %d" % [int(row["hits"]), roundi(row["total"])]
		elif int(row["ticks"]) > 1:
			total += " per tick, x%d ticks = %d" % [int(row["ticks"]), roundi(row["total"])]
		lines.append(total)
		for x in row["extra"]:
			lines.append("  " + str(x))
	if not rows.is_empty() and rows.any(func(r: Dictionary) -> bool: return r["kind"] == "damage"):
		lines.append("(before the target's defence and prayers)")
	var parts: Array[String] = []
	var total_cd := c.ability_cooldown(key, ab)
	if total_cd > 0.0:
		parts.append("Cooldown %.1fs" % total_cd)
	var cost := float(ab.get("spec_cost", 0.0))
	if cost > 0.0:
		parts.append("Costs %d%% special attack energy" % int(cost))
	if not parts.is_empty():
		lines.append("")
		lines.append(", ".join(parts))
	if key == "r":
		lines.append("Ranks unlock at levels 6, 11 and 16.")
	return UiStyle.wrap("\n".join(lines))
