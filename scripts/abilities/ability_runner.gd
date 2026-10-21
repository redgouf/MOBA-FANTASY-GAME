class_name AbilityRunner
extends RefCounted
## Executes data-driven abilities from data/champions.json.
## An ability is a list of effects; each effect has a "type" handled below.
## See docs/ABILITIES.md for the full effect reference.


static func execute(caster: Champion, ab: Dictionary, target: Unit, point: Vector3) -> void:
	var ctx := {"self_cost": 0.0}
	for effect in ab.get("effects", []):
		var delay := float(effect.get("delay", 0.0))
		if delay > 0.0:
			var run := func() -> void:
				if is_instance_valid(caster) and not caster.is_dead:
					apply_effect(caster, effect, target, point, ctx)
			caster.get_tree().create_timer(delay).timeout.connect(run)
		else:
			apply_effect(caster, effect, target, point, ctx)


static func apply_effect(caster: Champion, e: Dictionary, target: Unit, point: Vector3, ctx: Dictionary) -> void:
	match str(e.get("type", "")):
		"damage":
			_damage(caster, e, target, point, ctx)
		"heal":
			_heal(caster, e, target, point, ctx)
		"self_cost":
			var cost := caster.health * float(e.get("pct_current_health", 0.0))
			caster.health = maxf(1.0, caster.health - cost)
			ctx["self_cost"] = cost
		"status":
			for u in _status_targets(caster, e, target, point):
				if randf() <= float(e.get("chance", 1.0)):
					u.add_status(_status_id(caster, e), str(e.get("kind", "")), float(e.get("amount", 0.0)),
						float(e.get("duration", 1.0)), caster, e.get("data", {}))
		"dash":
			_dash(caster, e, target, point)
		"knockback":
			if _valid(target) and target != caster:
				var dir := target.global_position - caster.global_position
				dir.y = 0.0
				dir = dir.normalized() if dir.length() > 0.01 else caster.forward()
				target.start_dash(target.global_position + dir * float(e.get("distance", 3.0)), 24.0)
		"spec_transfer":
			if _valid(target) and target is Champion:
				var ally := target as Champion
				ally.spec = minf(100.0, ally.spec + float(e.get("amount", 25.0)))
		"summon":
			_summon(caster, e)
		"toggle_form":
			caster.toggle_form()
		"taunt":
			for u in collect_area(caster, e.get("area", {}), target, point, false):
				u.add_status("taunt", "taunt", 0.0, float(e.get("duration", 1.0)), caster)
		_:
			push_warning("AbilityRunner: unknown effect type '%s'" % e.get("type", ""))


# --- Damage ------------------------------------------------------------------

static func _damage(caster: Champion, e: Dictionary, target: Unit, point: Vector3, ctx: Dictionary) -> void:
	var area: Dictionary = e.get("area", {})
	var center := area_center(caster, area, target, point)
	var targets: Array[Unit] = []
	if area.is_empty():
		if _valid(target) and target.team != caster.team:
			targets.append(target)
	else:
		targets = collect_area(caster, area, target, point, false)
	var hits := maxi(1, int(e.get("hits", 1)))
	var interval := float(e.get("hit_interval", 0.15))
	for t in targets:
		var mults := _hit_multipliers(hits, bool(e.get("cascade", false)), float(e.get("miss_chance", 0.25)))
		for h in hits:
			var m: float = mults[h]
			if h == 0:
				_hit(caster, e, t, center, ctx, m)
			else:
				var later := func() -> void:
					_hit(caster, e, t, center, ctx, m)
				caster.get_tree().create_timer(interval * h).timeout.connect(later)


## Dragon claws style cascade: a missed hit rolls its damage into the next one.
static func _hit_multipliers(hits: int, cascade: bool, miss_chance: float) -> Array[float]:
	var out: Array[float] = []
	var carry := 0.0
	for i in hits:
		if cascade and i < hits - 1 and randf() < miss_chance:
			out.append(0.0)
			carry += 1.0
		else:
			out.append(1.0 + carry)
			carry = 0.0
	return out


static func compute_amount(caster: Champion, e: Dictionary, t: Unit) -> float:
	var amount := float(e.get("base", 0.0)) + float(e.get("base_per_level", 0.0)) * float(caster.level - 1)
	var ratio: Dictionary = e.get("ratio", {})
	amount += float(ratio.get("damage", 0.0)) * caster.get_damage()
	amount += float(ratio.get("magic_power", 0.0)) * caster.get_magic_power()
	var pct_part := float(e.get("pct_current_health", 0.0)) * t.health + float(e.get("pct_max_health", 0.0)) * t.max_health
	if e.has("cap"):
		pct_part = minf(pct_part, float(e["cap"]))
	amount += pct_part
	if e.has("missing_health_bonus"):
		amount *= 1.0 + (1.0 - caster.health_ratio()) * float(e["missing_health_bonus"])
	var low: Dictionary = e.get("bonus_below_health", {})
	if not low.is_empty() and t.health_ratio() < float(low.get("threshold", 0.3)):
		amount *= float(low.get("mult", 1.5))
	return amount


static func _hit(caster: Champion, e: Dictionary, t: Unit, center: Vector3, ctx: Dictionary, mult: float) -> void:
	if not is_instance_valid(caster) or not _valid(t):
		return
	if mult <= 0.0:
		t._spawn_hitsplat(0.0, DamageInfo.new())
		return
	var amount := compute_amount(caster, e, t) * mult
	var area: Dictionary = e.get("area", {})
	if bool(e.get("falloff", false)) and not area.is_empty():
		var r := float(area.get("radius", 3.0))
		amount *= 1.0 - 0.5 * clampf(Unit.flat_distance(center, t.global_position) / r, 0.0, 1.0)
	var style := Combat.style_from_string(str(e.get("style", Combat.style_name(caster.attack_style))))
	var info := DamageInfo.make(amount, style, caster)
	info.is_ability = true
	info.is_true = bool(e.get("true", false))
	info.ignores_prayer = bool(e.get("ignores_prayer", false))
	info.armor_pen = caster.armor_pen + float(e.get("armor_pen", 0.0))
	info.crit_mult = float(e.get("crit_mult", 1.0))
	caster.modify_outgoing(info, t)
	var dealt := t.take_damage(info)
	if e.has("lifesteal"):
		caster.heal(dealt * float(e["lifesteal"]))
	if e.has("shred_ratio") and not t.is_dead:
		t.add_status("shred:%d" % caster.get_instance_id(), "armor_flat", -dealt * float(e["shred_ratio"]),
			float(e.get("shred_duration", 6.0)), caster)
	for st in e.get("target_statuses", []):
		if t.is_dead:
			break
		if randf() > float(st.get("chance", 1.0)):
			continue
		var kind := str(st.get("kind", ""))
		var id := str(st.get("id", "%s:%d" % [kind, caster.get_instance_id()]))
		t.add_status(id, kind, float(st.get("amount", 0.0)), float(st.get("duration", 1.0)), caster, st.get("data", {}))


# --- Other effects -----------------------------------------------------------

static func _heal(caster: Champion, e: Dictionary, target: Unit, point: Vector3, ctx: Dictionary) -> void:
	var recipients: Array[Unit] = []
	var area: Dictionary = e.get("area", {})
	if not area.is_empty():
		recipients = collect_area(caster, area, target, point, true)
	elif str(e.get("on", "self")) == "target" and _valid(target):
		recipients.append(target)
	else:
		recipients.append(caster)
	for u in recipients:
		var amount := float(e.get("base", 0.0)) + float(e.get("base_per_level", 0.0)) * float(caster.level - 1)
		amount += float(e.get("ratio", {}).get("magic_power", 0.0)) * caster.get_magic_power()
		amount += float(e.get("pct_missing", 0.0)) * (u.max_health - u.health)
		amount += float(e.get("pct_max", 0.0)) * u.max_health
		amount += float(ctx.get("self_cost", 0.0)) * float(e.get("from_self_cost_mult", 0.0))
		var over := float(e.get("over_time", 0.0))
		if over > 0.0:
			u.add_status("heal:%d" % caster.get_instance_id(), "heal_over_time", amount / over, over, caster)
		else:
			u.heal(amount)


static func _dash(caster: Champion, e: Dictionary, target: Unit, point: Vector3) -> void:
	if caster.has_status("tele_block"):
		return
	var dest: Vector3
	if str(e.get("to", "point")) == "target" and _valid(target):
		var dir := target.global_position - caster.global_position
		dir.y = 0.0
		var stop := float(e.get("stop_distance", caster.radius + target.radius))
		dest = target.global_position - (dir.normalized() * stop if dir.length() > 0.01 else Vector3.ZERO)
	else:
		var d := point - caster.global_position
		d.y = 0.0
		if d.length() < 0.01:
			d = caster.forward()
		var dist := minf(d.length(), float(e.get("distance", d.length())))
		dest = caster.global_position + d.normalized() * dist
	if bool(e.get("teleport", false)):
		caster.global_position = Vector3(dest.x, 0.0, dest.z)
		caster.snap_to_navmesh()
	else:
		caster.start_dash(dest, float(e.get("speed", 24.0)), bool(e.get("ignore_walls", false)))


static func _summon(caster: Champion, e: Dictionary) -> void:
	var def := GameData.unit_def("summons", str(e.get("unit", "")))
	if def.is_empty():
		push_warning("AbilityRunner: unknown summon '%s'" % e.get("unit", ""))
		return
	var s := Structure.new()
	s.init_structure("summon", def, caster.team, str(def.get("name", "Summon")))
	s.lifetime = float(e.get("duration", 8.0))
	s.targets_neutral = true
	s.owner_champion = caster
	caster.get_parent().add_child(s)
	s.global_position = caster.global_position + caster.forward() * 1.5


# --- Targeting ---------------------------------------------------------------

static func _valid(u: Variant) -> bool:
	return is_instance_valid(u) and u is Unit and not u.is_dead


static func _status_id(caster: Champion, e: Dictionary) -> String:
	return str(e.get("status_id", "%s:%d" % [e.get("kind", ""), caster.get_instance_id()]))


static func _status_targets(caster: Champion, e: Dictionary, target: Unit, point: Vector3) -> Array[Unit]:
	var out: Array[Unit] = []
	match str(e.get("on", "self")):
		"self":
			out.append(caster)
		"target":
			if _valid(target):
				out.append(target)
		"area_allies":
			out = collect_area(caster, e.get("area", {}), target, point, true)
		"area_enemies":
			out = collect_area(caster, e.get("area", {}), target, point, false)
	return out


static func area_center(caster: Unit, area: Dictionary, target: Unit, point: Vector3) -> Vector3:
	match str(area.get("center", "point")):
		"self":
			return caster.global_position
		"target":
			return target.global_position if _valid(target) else point
	return point


## Units inside a circle, cone (from the caster toward the point) or line.
static func collect_area(caster: Unit, area: Dictionary, target: Unit, point: Vector3, allies: bool) -> Array[Unit]:
	var out: Array[Unit] = []
	if area.is_empty():
		return out
	var center := area_center(caster, area, target, point)
	var shape := str(area.get("shape", "circle"))
	var r := float(area.get("radius", 3.0))
	var dir := point - caster.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else caster.forward()
	for n in caster.get_tree().get_nodes_in_group("units"):
		var u := n as Unit
		if u == null or u.is_dead:
			continue
		if allies:
			if u.team != caster.team:
				continue
		elif u.team == caster.team or not u.is_damageable():
			continue
		var to := u.global_position - caster.global_position
		to.y = 0.0
		match shape:
			"circle":
				if Unit.flat_distance(center, u.global_position) <= r + u.radius:
					out.append(u)
			"cone":
				var half := deg_to_rad(float(area.get("angle", 90.0)) * 0.5)
				if to.length() <= r + u.radius and (to.length() < 0.5 or dir.angle_to(to.normalized()) <= half):
					out.append(u)
			"line":
				var along := to.dot(dir)
				var length := float(area.get("length", 10.0))
				var width := float(area.get("width", 2.0))
				if along >= -u.radius and along <= length + u.radius and (to - dir * along).length() <= width * 0.5 + u.radius:
					out.append(u)
	var max_targets := int(area.get("max_targets", 0))
	if max_targets > 0 and out.size() > max_targets:
		out.resize(max_targets)
	return out
