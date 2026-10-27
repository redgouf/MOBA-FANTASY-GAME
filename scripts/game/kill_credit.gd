class_name KillCredit
extends RefCounted
## Who gets a champion kill, as in League of Legends: the LAST champion to
## affect the victim within the window gets the kill, whoever lands the
## final blow, so a minion, turret or monster finishing off a champion that
## an enemy champion hit a moment ago still pays that champion. Everyone else
## who hit them within the window gets an assist. If no enemy champion did
## anything in the window the victim is "executed": no kill, no assist, no
## kill gold (they just die). The window is 15 seconds on Summoner's Rift and
## every new hit refreshes that champion's time.

const WINDOW_SEC := 15.0


## The champion a unit's actions count for: itself, or the champion who owns
## the structure (a cannon, a planted prop...). null for minions, monsters and towers.
static func champion_of(u: Variant) -> Champion:
	if not is_instance_valid(u):
		return null
	if u is Champion:
		return u
	if u is Structure and is_instance_valid((u as Structure).owner_champion):
		return (u as Structure).owner_champion
	return null


## {"killer": Champion or null, "assists": Array[Champion], "executed": bool}.
## `final_blow` is whatever landed the killing hit; `now` is Combat.clock.
static func resolve(victim: Champion, final_blow: Unit, now: float) -> Dictionary:
	var recent := {}          # champion -> the time of their latest hit on the victim
	for entry in victim.recent_attackers.values():
		var c := champion_of(entry["unit"])
		if c == null or c == victim or c.team == victim.team:
			continue
		var t := float(entry["time"])
		if now - t > WINDOW_SEC:
			continue
		if not recent.has(c) or t > float(recent[c]):
			recent[c] = t
	var killer := champion_of(final_blow)
	if killer != null and (killer == victim or killer.team == victim.team):
		killer = null
	if killer == null:
		var best := -INF
		for c in recent:
			if float(recent[c]) > best:
				best = float(recent[c])
				killer = c
	var assists: Array[Champion] = []
	if killer != null:
		for c in recent:
			if c != killer:
				assists.append(c)
	return {"killer": killer, "assists": assists, "executed": killer == null}
