extends Node
## Authoritative round clock, scores and pilot ledger, independent of ship respawns.

signal score_changed(scores: Dictionary)
signal kill_logged(text: String, color: Color)
signal time_changed(remaining: float)
signal match_finished(winner: int)

const DRAW := -1

var scores := {GameConfig.TEAM_BLUE: 0, GameConfig.TEAM_RED: 0}
var remaining := GameConfig.MATCH_SECONDS
var running := false
var winner := DRAW
var pilots: Dictionary = {}

var _feed: Array[Dictionary] = []


func _process(delta: float) -> void:
	if not running:
		return
	_decay_feed(delta)
	remaining = maxf(0.0, remaining - delta)
	time_changed.emit(remaining)
	if remaining <= 0.0:
		finish_match()


func finish_match() -> void:
	if not running:
		return
	running = false
	winner = DRAW
	if scores[GameConfig.TEAM_BLUE] > scores[GameConfig.TEAM_RED]:
		winner = GameConfig.TEAM_BLUE
	elif scores[GameConfig.TEAM_RED] > scores[GameConfig.TEAM_BLUE]:
		winner = GameConfig.TEAM_RED
	match_finished.emit(winner)


func add_score(team: int) -> void:
	if not running or not scores.has(team):
		return
	scores[team] += 1
	score_changed.emit(scores)


func register_pilot(pilot_name: String, team: int) -> void:
	if not running or pilots.has(pilot_name):
		return
	pilots[pilot_name] = {
		"name": pilot_name, "team": team, "kills": 0, "deaths": 0,
		"damage": 0.0, "shots": 0, "hits": 0,
	}


func record_shot(pilot_name: String) -> void:
	if running and pilots.has(pilot_name):
		pilots[pilot_name].shots += 1


func record_damage(pilot_name: String, damage: float) -> void:
	if not running or not pilots.has(pilot_name):
		return
	pilots[pilot_name].damage += maxf(0.0, damage)
	# Count only bolt hits; collisions have no ship attacker.
	pilots[pilot_name].hits += 1


func log_kill(killer_name: String, killer_team: int, victim_name: String, victim_team: int, weapon := "LASER") -> void:
	if not running:
		return
	if pilots.has(victim_name):
		pilots[victim_name].deaths += 1
	var enemy_kill := killer_team >= 0 and killer_team != victim_team and killer_name != victim_name
	if enemy_kill and pilots.has(killer_name):
		pilots[killer_name].kills += 1
	var color := GameConfig.team_color(killer_team)
	var text := ""
	if killer_name == "":
		text = "%s  /  %s" % [victim_name, "COLLISION" if weapon == "COLLISION" else "LOST TO HAZARD"]
		color = Color(0.72, 0.77, 0.84)
	else:
		text = "%s  >>  %s" % [killer_name, victim_name]
	_feed.push_front({"text": text, "color": color, "life": GameConfig.KILLFEED_TIME,
		"killer": killer_name, "victim": victim_name, "cause": weapon})
	while _feed.size() > GameConfig.KILLFEED_MAX:
		_feed.pop_back()
	kill_logged.emit(text, color)
	if enemy_kill:
		add_score(killer_team)


func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for pilot: Dictionary in pilots.values():
		rows.append(pilot.duplicate())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team < b.team
		if a.kills != b.kills:
			return a.kills > b.kills
		if a.deaths != b.deaths:
			return a.deaths < b.deaths
		return String(a.name) < String(b.name)
	)
	return rows


func _decay_feed(delta: float) -> void:
	for entry: Dictionary in _feed:
		entry.life -= delta
	while not _feed.is_empty() and _feed[_feed.size() - 1].life <= 0.0:
		_feed.pop_back()


func get_feed() -> Array[Dictionary]:
	return _feed


func reset_match() -> void:
	scores = {GameConfig.TEAM_BLUE: 0, GameConfig.TEAM_RED: 0}
	remaining = GameConfig.MATCH_SECONDS
	running = true
	winner = DRAW
	pilots.clear()
	_feed.clear()
	score_changed.emit(scores)
	time_changed.emit(remaining)
