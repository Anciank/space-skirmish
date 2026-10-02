extends Node
## Tracks the running match: teams, scores, kill feed and the round timer.

signal score_changed(scores: Dictionary)
signal kill_logged(text: String, color: Color)
signal time_changed(remaining: float)
signal match_finished(winner: int)

var scores := {GameConfig.TEAM_BLUE: 0, GameConfig.TEAM_RED: 0}
var remaining := GameConfig.MATCH_SECONDS
var running := false

var _feed: Array[Dictionary] = []


func _ready() -> void:
	running = true


func _process(delta: float) -> void:
	_decay_feed(delta)
	if not running or remaining <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	time_changed.emit(remaining)
	if remaining <= 0.0:
		running = false
		var winner := GameConfig.TEAM_BLUE
		if scores[GameConfig.TEAM_RED] > scores[GameConfig.TEAM_BLUE]:
			winner = GameConfig.TEAM_RED
		match_finished.emit(winner)


func add_score(team: int) -> void:
	scores[team] = int(scores.get(team, 0)) + 1
	score_changed.emit(scores)


func log_kill(killer_name: String, killer_team: int, victim_name: String, victim_team: int, weapon := "LASER") -> void:
	var color := GameConfig.team_color(killer_team)
	var text := ""
	if killer_name == "":
		text = "%s [%s] destroyed by the void" % [victim_name, weapon]
	else:
		text = "%s  >>  %s" % [killer_name, victim_name]
	_feed.push_front({"text": text, "color": color, "life": GameConfig.KILLFEED_TIME})
	while _feed.size() > GameConfig.KILLFEED_MAX:
		_feed.pop_back()
	kill_logged.emit(text, color)


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
	_feed.clear()
	score_changed.emit(scores)
	time_changed.emit(remaining)
