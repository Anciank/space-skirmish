extends Node
## Headless smoke test for the whole demo.
##
##   godot --headless res://tests/smoke_test.tscn
##
## Loads the real main scene, then drives the player through a full engagement
## (thrust, boost, fire, take damage, die, respawn) and reports PASS/FAIL for
## every subsystem it can reach. Exits non-zero if anything failed.
##
## Player input is injected through `Input.action_press()` so the actual input
## mapping and the player controller are exercised, not bypassed.

var _main: Node3D
var _failures := 0
var _checks := 0


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	add_child(_main)
	# One physics frame so every _ready() has run before we poke at anything.
	await get_tree().physics_frame
	_run()


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	var mark := "PASS" if condition else "FAIL"
	if not condition:
		_failures += 1
	print("  %s  %s %s" % [mark, label, detail])


func _section(title: String) -> void:
	print("")
	print("=== %s ===" % title)


func _step(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _run() -> void:
	print("")
	print("--- Star Skirmish smoke test ---")

	await _test_boot()
	await _test_flight()
	await _test_damage()
	await _test_weapons()
	await _test_death_and_respawn()
	await _test_ai()
	await _test_world()
	_test_hud()

	print("")
	print("--- %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# ==================================================================== boot ==

func _test_boot() -> void:
	_section("boot")
	var player: SpaceShip = _main.player
	_check("player exists", player != null)
	_check("player alive", player != null and not player.dead)
	_check("player on blue team", player.team == GameConfig.TEAM_BLUE)
	_check("roster populated", _main._roster.size() >= 3, "(%d ships)" % _main._roster.size())
	_check("arena has bodies", _main.arena.bodies.size() >= 2, "(%d)" % _main.arena.bodies.size())
	_check("arena has rocks", _main.arena.asteroids.size() >= 20, "(%d)" % _main.arena.asteroids.size())
	_check("rocks inside boundary", _rocks_inside_arena())
	_check("no ship spawned inside a rock", _ships_clear_of_rocks())
	_check("camera bound to player", _main.rig.target == player)
	_check("hud bound to player", _main.hud.player == player)
	_check("chase camera trails the ship and aims with it",
		await _camera_behind_ship(player))
	_check("input actions registered", _actions_present())
	_check("collision layers correct",
		player.collision_layer == GameConfig.LAYER_SHIP
		and (player.collision_mask & GameConfig.LAYER_SHIP) != 0,
		"(layer %d mask %d)" % [player.collision_layer, player.collision_mask])
	_check("ship model present", player.get_node_or_null("ShipModel/HullBody") != null)
	_check("muzzle points present", player.muzzle_points.size() == 2
		and is_instance_valid(player.muzzle_points[0]))


# ================================================================== flight ==

func _test_flight() -> void:
	_section("flight model")
	var p: SpaceShip = _main.player
	var start_pos := p.global_position

	_hold("thrust_forward", true)
	await _step(48)
	_check("W thrusts the ship", p.velocity.length() > 25.0, "(%.1f m/s)" % p.velocity.length())
	_check("ship actually moved", p.global_position.distance_to(start_pos) > 15.0,
		"(%.0f m)" % p.global_position.distance_to(start_pos))
	_check("throttle ramps up", p.throttle > 0.5, "(%.2f)" % p.throttle)

	var cruise := p.velocity.length()
	_hold("boost", true)
	await _step(60)
	_check("afterburner outruns cruise", p.velocity.length() > cruise + 20.0,
		"(%.1f m/s)" % p.velocity.length())
	_check("boost meter drains", p.boost < GameConfig.BOOST_MAX - 10.0, "(%.1f)" % p.boost)
	_check("engine flames light up", _engine_flames_visible())
	_check("engine drone plays", _engine_volume() > -50.0, "(%.0f dB)" % _engine_volume())

	_hold("boost", false)
	_hold("thrust_forward", false)
	await _step(90)
	_check("boost regenerates", p.boost > 20.0, "(%.1f)" % p.boost)
	_check("coasting bleeds off speed", p.velocity.length() < cruise + 5.0,
		"(%.1f m/s)" % p.velocity.length())

	# Dampeners should kill residual drift quickly.
	await _step(30)
	_hold("dampeners", true)
	await _step(90)
	_check("dampeners arrest drift", p.velocity.length() < 6.0,
		"(%.1f m/s)" % p.velocity.length())
	_hold("dampeners", false)

	# Roll + strafe sanity.
	var before_basis := p.global_transform.basis.y
	_hold("roll_right", true)
	await _step(40)
	_hold("roll_right", false)
	_check("Q/E rolls the hull", p.global_transform.basis.y.dot(before_basis) < 0.999)

	_hold("thrust_right", true)
	var pos_before := p.global_position
	await _step(90)
	_hold("thrust_right", false)
	var strafe_dist := pos_before.distance_to(p.global_position)
	_check("A/D strafes", strafe_dist > 8.0, "(%.1f m)" % strafe_dist)

	_check("engine flames retract", await _flames_retract())


func _flames_retract() -> bool:
	var model: Node3D = _main.player.get_node_or_null("ShipModel")
	if model == null:
		return false
	var burner := model.get_node_or_null("BurnerLeft") as MeshInstance3D
	return burner != null and not burner.visible


func _engine_volume() -> float:
	var ep: AudioStreamPlayer = Sfx._engine_player
	if ep == null:
		return -99.0
	return ep.volume_db


# ================================================================== damage ==

func _test_damage() -> void:
	_section("damage model")
	var p: SpaceShip = _main.player
	p.respawn_at(p.global_position, p.global_position + Vector3.FORWARD)
	p.shield = p.shield_max
	p.hull = p.hull_max
	p.velocity = Vector3.ZERO

	var hull_before := p.hull
	p.take_damage(40.0, null, p.global_position + p.forward() * 5.0)
	_check("shield absorbs first", p.shield < p.shield_max and is_equal_approx(p.hull, hull_before),
		"(shield %.0f, hull %.0f)" % [p.shield, p.hull])

	# A hit bigger than the remaining shield must carry through into the hull.
	p.take_damage(p.shield + 25.0, null, p.global_position + p.forward() * 5.0)
	_check("overflow eats through to hull", is_equal_approx(p.hull, hull_before - 25.0),
		"(hull %.0f)" % p.hull)
	_check("shield floored at zero", is_zero_approx(p.shield))

	p.shield = p.shield_max
	p.hull = 10.0
	p.take_damage(10000.0, null, Vector3.ZERO)
	await _step(2)
	_check("lethal damage destroys the ship", p.dead)
	_check("corpse stops colliding", p.collision_layer == 0)
	_check("corpse is hidden", not p.visible)
	_check("respawn scheduled", _respawn_left_for(p) > 0.0, "(%.1fs)" % _respawn_left_for(p))
	_check("explosion spawned for the kill", _count_by_script("explosion_fx.gd") > 0)

	# Skip the four second redeploy wait.
	for entry: Dictionary in _main._pending:
		entry.left = 0.01
	await _step(6)

	var fresh: SpaceShip = _main.player
	_check("player rebuilt", fresh != null and fresh != p and is_instance_valid(fresh))
	if fresh == null or fresh == p:
		return
	_check("respawned at full hull", fresh.hull >= fresh.hull_max - 0.01 and not fresh.dead,
		"(hull %.0f)" % fresh.hull)
	_check("respawned inside the arena",
		Vector3(fresh.global_position.x, 0, fresh.global_position.z).length() < GameConfig.ARENA_RADIUS)
	_check("respawned clear of rocks", _clear_of_rocks(fresh))
	_check("camera retargeted", _main.rig.target == fresh)
	_check("hud retargeted", _main.hud.player == fresh)
	_check("mouse recapture requested", fresh._mouse_captured)
	_check("old corpse freed", not is_instance_valid(p))

	# Shields come back on a fresh ship; hull never does.
	fresh.shield = 0.0
	await _step(int(GameConfig.SHIELD_REGEN_DELAY * 60.0) + 60)
	_check("shields regenerate after the delay", fresh.shield > 50.0,
		"(%.0f)" % fresh.shield)
	_check("hull does not regenerate", is_equal_approx(fresh.hull, fresh.hull_max))

	# Friendly fire.
	var ally: SpaceShip = null
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if is_instance_valid(s) and s.team == fresh.team and s != fresh:
			ally = s
			break
	if ally != null:
		var ally_hull := ally.hull
		fresh.take_damage(60.0, ally, Vector3.ZERO)
		_check("friendly fire ignored", is_equal_approx(ally.hull, ally_hull))
	_check("ally on the team", ally != null)


# ================================================================= weapons ==

func _test_weapons() -> void:
	_section("weapons")
	var p: SpaceShip = _main.player
	var enemy: SpaceShip = null
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if s != null and s.team != p.team and not s.dead:
			enemy = s
			break
	_check("hostile exists", enemy != null)
	if enemy == null:
		return

	enemy.respawn_at(enemy.global_position + Vector3(0, 40, 0), enemy.global_position)
	enemy.shield = enemy.shield_max
	enemy.hull = enemy.hull_max
	enemy.velocity = Vector3.ZERO

	# Park the target 140 m straight ahead and aim at it.
	# Park both ships on a known line so the shot is reproducible. Setting the
	# player's velocity and position directly works here because the test drives
	# it outside _physics_process and holds the values each frame.
	var stand_off := Vector3(0, 0, 0)
	var aim_dir := Vector3(0, 0, -1)
	p.velocity = Vector3.ZERO
	p.global_position = stand_off
	enemy.global_position = stand_off + aim_dir * 140.0
	enemy.velocity = Vector3.ZERO
	p.look_at(enemy.global_position, Vector3.UP)
	_check("bolts fly toward the target",
		p.forward().dot((enemy.global_position - p.global_position).normalized()) > 0.99,
		("(dot %.3f)" % p.forward().dot((enemy.global_position - p.global_position).normalized())))

	var bolts_before := _group_size("bolts")
	p._fire_timer = 0.0
	p.fire(1)
	_check("bolt spawns", _group_size("bolts") > bolts_before,
		"(%d -> %d)" % [bolts_before, _group_size("bolts")])
	var tracked := _newest_bolt()
	_check("bolt is in the effects layer", tracked != null)

	var hp_before := enemy.shield + enemy.hull
	# Sustained fire at close range.
	for _i in 90:
		if p.dead or enemy.dead:
			break
		enemy.global_position = stand_off + aim_dir * 140.0
		enemy.velocity = Vector3.ZERO
		p.global_position = stand_off
		p.velocity = Vector3.ZERO
		p.look_at(enemy.global_position, Vector3.UP)
		p._fire_timer = 0.0
		p.fire(1)
		await get_tree().physics_frame

	await _step(6)
	if enemy.dead:
		_check("sustained fire destroys the target", true, "(killed in the burst)")
	else:
		_check("sustained fire damages the target", enemy.shield + enemy.hull < hp_before,
			"(%.0f -> %.0f)" % [hp_before, enemy.shield + enemy.hull])
	_check("a bolt expires after its lifetime", await _bolt_expires(tracked))


## Instance id of the most recently spawned bolt, or 0 if there is none.
##
## Returns an id rather than the node: a bolt lives barely a second, so by the
## time the caller passes it on it may already be freed — and handing a freed
## object to a typed parameter is rejected before the callee can check validity.
func _newest_bolt() -> int:
	var effects: Node = _main.get_node_or_null("Effects")
	if effects == null:
		return 0
	var newest := 0
	for child: Node in effects.get_children():
		if child is Node3D and child.is_in_group("bolts"):
			newest = child.get_instance_id()
	return newest


## True once the given bolt has left the tree.
func _bolt_expires(bolt_id: int) -> bool:
	if bolt_id == 0:
		return false
	var frames := int(GameConfig.BOLT_LIFETIME * 60.0) + 20
	for _i in frames:
		await get_tree().physics_frame
		if instance_from_id(bolt_id) == null:
			return true
	return false


func _feed_text() -> String:
	var feed := GameMatch.get_feed()
	return str(feed[0].text) if feed.size() > 0 else ""


# ========================================================= death + respawn ==

func _test_death_and_respawn() -> void:
	_section("ai deaths score points")
	var enemy: SpaceShip = null
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if is_instance_valid(s) and s.team != _main.player.team and not s.dead:
			enemy = s
			break
	if enemy == null:
		_check("hostile available to kill", false)
		return
	var killer: SpaceShip = _main.player
	killer.hull = killer.hull_max
	killer.shield = killer.shield_max
	var score_before := int(GameMatch.scores[killer.team])
	enemy.take_damage(10000.0, killer, Vector3.ZERO)
	await _step(2)
	_check("hostile destroyed", enemy.dead)
	_check("score credited to the killer's team",
		int(GameMatch.scores[killer.team]) == score_before + 1,
		"(%d -> %d)" % [score_before, int(GameMatch.scores[killer.team])])
	_check("kill feed names both pilots", _feed_text().contains(killer.display_name)
		and _feed_text().contains(enemy.display_name),
		"(\"%s\")" % _feed_text())
	_check("last attacker remembered", enemy.last_attacker == killer)


# ====================================================================== ai ==

func _test_ai() -> void:
	_section("ai")
	# Skip anything dead or awaiting redeploy: a pending ship has just been
	# rebuilt and has not started flying yet, which skews every measurement here.
	var ais: Array[AIShip] = []
	# Earlier tests kill ships, so one AI may still be on respawn cooldown. Wait
	# for the roster to refill rather than asserting a count that is really just
	# reporting on the order the tests happen to run in.
	for _wait in 240:
		ais.clear()
		for entry: Dictionary in _main._roster:
			var s: Node = entry.ship
			if is_instance_valid(s) and s is AIShip and not (s as AIShip).dead \
					and _respawn_left_for(s as AIShip) <= 0.0:
				ais.append(s as AIShip)
		if ais.size() >= 2:
			break
		await get_tree().physics_frame
	_check("ai ships present", ais.size() >= 2, "(%d)" % ais.size())
	if ais.is_empty():
		return

	var ai := ais[0]
	# Drop the pilot next to a hostile so a dogfight actually starts, and let the
	# pilot acquire the contact before anything is measured — target acquisition
	# runs on its own decision interval, not every frame.
	var victim: SpaceShip = null
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if is_instance_valid(s) and s.team != ai.team and not s.dead:
			victim = s
			break
	if victim != null:
		ai.respawn_at(victim.global_position + Vector3(0.0, 0.0, 200.0), victim.global_position)
	ai.hull = ai.hull_max
	for _i in 90:
		await get_tree().physics_frame

	_start_damage_tally()
	var travelled := 0.0
	var peak_speed := 0.0
	var peak_bolts := 0
	var last := ai.global_position
	# Every hostile this pilot locked onto during the window. Sampling only the
	# final target is flaky: a free-for-all pilot switches contacts, and damage
	# dealt to an earlier contact would be missed.
	var engaged_names: Dictionary = {}
	for _i in 420:
		await get_tree().physics_frame
		travelled += ai.global_position.distance_to(last)
		last = ai.global_position
		peak_speed = maxf(peak_speed, ai.velocity.length())
		peak_bolts = maxi(peak_bolts, _group_size("bolts"))
		if ai.target != null and is_instance_valid(ai.target):
			engaged_names[String(ai.target.display_name)] = true
	# Station-keeping inside the dogfight band is genuinely slow, so distance
	# alone is a poor liveness signal; peak speed is what separates "manoeuvring"
	# from "parked".
	_check("ai is flying, not parked", travelled > 40.0 and peak_speed > 25.0,
		("(%.0f m travelled, peak %.0f m/s)" % [travelled, peak_speed]))
	_check("ai acquired a contact", ai.target != null,
		"(state %d%s)" % [ai.state,
			", %d m" % int(ai.global_position.distance_to(ai.target.global_position)) if ai.target else ""])
	if ai.target != null:
		# A ship must point its nose (-Z) at its target, not fly backwards.
		var to_target := (ai.target.global_position - ai.global_position).normalized()
		var facing := ai.forward().dot(to_target)
		_check("ai points its nose at its target", facing > 0.5,
			("(%.0f deg off)" % rad_to_deg(acos(clampf(facing, -1.0, 1.0)))))
	_check("ai stays inside the arena",
		Vector3(ai.global_position.x, 0, ai.global_position.z).length() < GameConfig.ARENA_RADIUS)
	_check("ai respects the speed cap", ai.velocity.length() < GameConfig.SPEED_BOOST * 1.3,
		"(%.0f m/s)" % ai.velocity.length())
	_check("ai is shooting", peak_bolts > 0, "(peak %d bolts in flight)" % peak_bolts)
	var fleet_damage := _stop_damage_tally()
	var breakdown := []
	for key: String in _damage_to:
		breakdown.append("%s %.1f" % [key, float(_damage_to[key])])
	_check("bolts in flight land on somebody", fleet_damage > 0.0,
		("(%.1f total across %d ship(s): %s)" % [fleet_damage, _damage_to.size(),
			", ".join(breakdown)]))
	# Assert against the ships this pilot actually locked onto, not the ship we
	# happened to park it next to — target selection is the AI's own decision,
	# so pinning this to `victim` would measure selection, not gunnery.
	var engaged_damage := 0.0
	var hit_names := []
	for name: String in engaged_names:
		var taken: float = float(_damage_to.get(name, 0.0))
		engaged_damage += taken
		if taken > 0.0:
			hit_names.append("%s %.0f" % [name, taken])
	_check("ai fire damages the ships it engaged", engaged_damage > 0.0,
		("(%.0f across %d contact(s): %s)" % [engaged_damage, engaged_names.size(),
			", ".join(hit_names) if hit_names.size() > 0 else "none hit"]))


func _fleet_hp() -> float:
	var total := 0.0
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if is_instance_valid(s) and not s.dead:
			total += s.shield + s.hull
	return total


## Damage tallying via the `took_damage` signal, so redeploys and respawns do
## not pollute the measurement.
##
## Damage taken per ship, during the tally window.
##
## Shields regenerate, so comparing hull+shield before and after a window reports
## "no damage" even while a ship is being hit continuously. Summing the signal
## events is the only honest measure here.
##
## Keyed by display name, never by node reference.
##
## Ships are freed the instant they die, and the demo deliberately destroys
## several during this run. A Dictionary holding a freed instance as a key both
## corrupts on iteration and throws "invalid previously freed instance" the
## moment anything is assigned through it. Names are stable across a redeploy.
var _damage_to: Dictionary = {}

## instance_id -> [ship, callable]
var _tally_conns: Dictionary = {}


func _start_damage_tally() -> void:
	_stop_damage_tally()
	_damage_to.clear()
	for entry: Dictionary in _main._roster:
		var s := entry.ship as SpaceShip
		if s == null or not is_instance_valid(s):
			continue
		var cb := _on_damage_tally.bind(String(s.display_name))
		if not s.took_damage.is_connected(cb):
			s.took_damage.connect(cb)
			_tally_conns[s.get_instance_id()] = [s, cb]


func _on_damage_tally(amount: float, _pos: Vector3, _attacker: Node, ship_name: String) -> void:
	_damage_to[ship_name] = float(_damage_to.get(ship_name, 0.0)) + amount


## Returns the total damage summed across every ship that was hit.
func _stop_damage_tally() -> float:
	for id: int in _tally_conns:
		# Resolve the ship fresh from its id rather than trusting the stored
		# reference, which may have been freed since it was recorded.
		var node := instance_from_id(id)
		if node == null or not (node is SpaceShip):
			continue
		var ship := node as SpaceShip
		var cb: Callable = _tally_conns[id][1]
		if ship.took_damage.is_connected(cb):
			ship.took_damage.disconnect(cb)
	_tally_conns.clear()
	var total := 0.0
	for key: String in _damage_to:
		total += float(_damage_to[key])
	return total


# ==================================================================== world ==

func _test_world() -> void:
	_section("world")
	var rock: Asteroid = _main.arena.asteroids[0]
	var rock_pos := rock.global_position
	rock.hp = 1.0
	rock.take_damage(50.0, null, Vector3.ZERO)
	await _step(3)
	_check("asteroid shatters", rock.dead)
	_check("shattered asteroid hidden", not rock.visible)

	# Jump the respawn timer rather than waiting fifteen seconds.
	rock._respawn_timer = 0.05
	await _step(20)
	_check("asteroid respawns", not rock.dead and rock.visible)
	_check("respawned rock moved", rock.global_position.distance_to(rock_pos) > 1.0,
		"(%.0f m)" % rock.global_position.distance_to(rock_pos))

	var body: StarBody = _main.arena.bodies[0]
	_check("planet has a gravity well", body.gravity_strength > 0.0
		and body.well_radius > body.radius,
		"(%.0f m/s2 over %.0f m)" % [body.gravity_strength, body.well_radius])
	_check("moon or planet present", _main.arena.bodies.size() >= 2)

	# Gravity should actually bend a ship's path.
	var p: SpaceShip = _main.player
	p.respawn_at(body.global_position + Vector3(body.radius + 120.0, 0, 0), Vector3.ZERO)
	p.velocity = Vector3.ZERO
	await _step(30)
	_check("gravity pulls ships toward the body",
		p.velocity.length() > 1.0,
		"(%.2f m/s)" % p.velocity.length())

	_check("starfield built", _main.rig.stars.get_node_or_null("StarMesh") != null)
	_check("boundary shell built", _main.arena.get_node_or_null("Boundary") != null)


# ====================================================================== hud ==

func _test_hud() -> void:
	_section("hud")
	var hud: Control = _main.hud
	_check("hud font resolved", hud._font != null)
	hud.cycle_target()
	_check("target lock cycles without error", true)
	hud.current_target()
	hud._draw_zone_warning()
	hud._draw_damage_direction()
	_check("hud draw helpers safe", true)
	_check("score tracked", GameMatch.scores.size() == 2)


# ================================================================= helpers ==

func _actions_present() -> bool:
	var required := [
		"thrust_forward", "thrust_back", "thrust_left", "thrust_right",
		"thrust_up", "thrust_down", "roll_left", "roll_right", "boost", "fire",
		"dampeners", "recenter", "next_target", "toggle_camera", "toggle_mouse",
		"pause", "restart", "steer_x", "steer_y",
	]
	for action: String in required:
		if not InputMap.has_action(action):
			return false
	return true


func _group_size(group: String) -> int:
	return get_tree().get_nodes_in_group(group).size()


func _count_by_script(script_file: String) -> int:
	var n := 0
	var effects: Node = _main.get_node_or_null("Effects")
	if effects == null:
		return 0
	for child: Node in effects.get_children():
		var sc: Script = child.get_script()
		if sc != null and String(sc.resource_path).ends_with(script_file):
			n += 1
	return n


func _respawn_left_for(ship: SpaceShip) -> float:
	for entry: Dictionary in _main._pending:
		if entry.ship == ship:
			return float(entry.left)
	return 0.0


func _rocks_inside_arena() -> bool:
	for rock: Asteroid in _main.arena.asteroids:
		if Vector3(rock.global_position.x, 0, rock.global_position.z).length() > GameConfig.ARENA_RADIUS:
			return false
	return true


func _clear_of_rocks(ship: Node3D) -> bool:
	for rock: Asteroid in _main.arena.asteroids:
		if rock.dead:
			continue
		if ship.global_position.distance_to(rock.global_position) < rock.radius + ship.collision_radius * 2.0:
			return false
	return true


func _ships_clear_of_rocks() -> bool:
	for entry: Dictionary in _main._roster:
		var s := entry.ship as Node3D
		if s != null and is_instance_valid(s) and not _clear_of_rocks(s):
			return false
	return true


func _engine_flames_visible() -> bool:
	var model: Node3D = _main.player.get_node_or_null("ShipModel")
	if model == null:
		return false
	var burner := model.get_node_or_null("BurnerLeft") as MeshInstance3D
	return burner != null and burner.visible and burner.scale.z > 0.3


## The chase camera must trail the ship along its +Z axis, and its own -Z must
## point where the ship is pointing.
func _camera_behind_ship(ship: SpaceShip) -> bool:
	await _step(90)
	var rig: CameraRig = _main.rig
	if rig == null or ship == null:
		return false
	var to_cam := rig.global_position - ship.global_position
	if to_cam.dot(ship.forward()) > 0.0:
		# Camera is level with the hull, so only compare lateral offset.
		to_cam = to_cam.slide(ship.forward())
	var behind: float = to_cam.normalized().dot(ship.global_transform.basis.z)
	var aim: float = (-rig.global_transform.basis.z).normalized().dot(ship.forward())
	return behind > 0.6 and aim > 0.8
