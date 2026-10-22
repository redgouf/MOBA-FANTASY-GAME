class_name PrayerBook
extends RefCounted
## The OSRS prayer book (data/rules.json "prayers"): what each prayer does in
## the MOBA, how fast it drains, and which one a build picks by default.
##
## Drain follows the OSRS formula: with drain resistance 60 + 2 x prayer bonus,
## one prayer point drains every 0.6s x resistance / (sum of the active
## prayers' drain effects). Piety (drain 24) with no bonus: a point every 1.5s.


static func all() -> Array:
	return GameData.rule("prayers", [])


static func find(id: String) -> Dictionary:
	for p in all():
		if str(p.get("id", "")) == id:
			return p
	return {}


static func by_name(prayer_name: String) -> Dictionary:
	for p in all():
		if str(p.get("name", "")) == prayer_name:
			return p
	return {}


## The protection prayer for a style (Combat.Style), e.g. "protect_from_melee".
static func protect_id(style: int) -> String:
	for p in all():
		if p.has("protect") and Combat.style_from_string(str(p["protect"])) == style:
			return str(p["id"])
	return ""


static func is_protect(id: String) -> bool:
	return find(id).has("protect")


static func drain_resistance(prayer_bonus: float) -> float:
	var cfg: Dictionary = GameData.rule("prayer_drain", {})
	return float(cfg.get("base_resistance", 60)) + float(cfg.get("per_bonus", 2)) * maxf(prayer_bonus, -29.0)


## Seconds per prayer point for a total drain effect (0 = no drain).
static func seconds_per_point(total_drain: float, prayer_bonus: float = 0.0) -> float:
	if total_drain <= 0.0:
		return INF
	var cfg: Dictionary = GameData.rule("prayer_drain", {})
	var tick := float(cfg.get("tick", 0.6))
	return tick * drain_resistance(prayer_bonus) / total_drain / maxf(float(cfg.get("rate_mult", 1.0)), 0.01)


## Prayers a build may pick at champion select: unlocked by its Prayer level.
## Builds with overheads (Z/X/C) already have every protection prayer, so
## those aren't offered as their one pick.
static func pickable(def: Dictionary) -> Array:
	var lvl := int(def.get("skills", {}).get("prayer", 1))
	var out: Array = []
	for p in all():
		if int(p.get("level", 99)) > lvl:
			continue
		if p.has("protect") and bool(def.get("overheads", false)):
			continue
		out.append(p)
	return out


static func can_pick(def: Dictionary, id: String) -> bool:
	for p in pickable(def):
		if str(p["id"]) == id:
			return true
	return false


## How useful a prayer is to a build of this style, for the default pick:
## damage for its own style first, then attack speed, then damage taken.
static func score(p: Dictionary, style: String) -> float:
	var s := 0.0
	if not p.has("style") or str(p["style"]) == style:
		s += float(p.get("damage", 0.0)) * 100.0 + float(p.get("attack_speed", 0.0)) * 60.0
		s -= float(p.get("damage_taken", 0.0)) * 80.0
	return s


## The default (and the bots') pick: the strongest prayer for the build's style.
static func default_for(def: Dictionary) -> String:
	var style := str(def.get("style", "melee"))
	var best := ""
	var best_score := -1.0
	for p in pickable(def):
		var s := score(p, style)
		if s > best_score or (is_equal_approx(s, best_score) and best != "" and int(p["level"]) > int(find(best)["level"])):
			best_score = s
			best = str(p["id"])
	return best


## One line saying what a prayer does in the game ("+10% melee damage, ...").
static func effect_text(p: Dictionary) -> String:
	if p.is_empty():
		return "no prayer"
	if p.has("text"):
		# "{amount}" and the like are filled from the prayer's (scaled) numbers.
		var t := str(p["text"])
		for k in p:
			if t.contains("{%s}" % k):
				t = t.replace("{%s}" % k, str(snappedf(float(p[k]), 0.1)).trim_suffix(".0"))
		return t
	var parts: Array[String] = []
	if p.has("protect"):
		parts.append("%d%% less %s damage taken" % [roundi(Combat.protect_prayer_reduction * 100.0), str(p["protect"])])
	if p.has("damage"):
		parts.append("+%d%% %s damage" % [roundi(float(p["damage"]) * 100.0), str(p.get("style", ""))])
	if p.has("attack_speed"):
		parts.append("+%d%% %s attack speed" % [roundi(float(p["attack_speed"]) * 100.0), str(p.get("style", ""))])
	if p.has("damage_taken"):
		parts.append("%d%% less damage taken" % roundi(-float(p["damage_taken"]) * 100.0))
	return ", ".join(parts)


## "1 point every 1.5s (a full bar lasts 2:28)".
static func drain_text(total_drain: float, prayer_bonus: float = 0.0, points: float = 99.0) -> String:
	var spp := seconds_per_point(total_drain, prayer_bonus)
	if spp == INF:
		return "no drain"
	return "1 point every %ss (%s lasts %s)" % [_num(spp), "a full bar" if points >= 99.0 else "%d points" % int(points), clock_text(spp * points)]


static func clock_text(seconds: float) -> String:
	if seconds == INF or seconds > 5999.0:
		return "99:59+"
	var s := int(seconds)
	return "%d:%02d" % [floori(seconds / 60.0), s % 60]


static func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


## Full tooltip for a prayer: effect, drain and the OSRS original.
static func tooltip(p: Dictionary, prayer_bonus: float = 0.0) -> String:
	if p.is_empty():
		return "No prayer"
	return "%s (Prayer %d)\n%s\nDrain %d: %s\nIn OSRS: %s" % [p["name"], int(p["level"]), effect_text(p),
		int(p["drain"]), drain_text(float(p["drain"]), prayer_bonus), p.get("osrs", "")]
