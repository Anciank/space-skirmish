# Star Skirmish

A 3D third-person space combat demo in Godot 4. Six fighters, two teams, a
bounded asteroid arena with small planets that have real gravity wells, and one
weapon: a twin laser autocannon.

Built to be a playable vertical slice rather than a tech demo — everything you
see (ships, rocks, planets, stars, sound effects) is generated in code. There
are no binary assets in the repository.

## Running it

```bash
godot --path . # or open project.godot in the Godot editor and press F5
```

## Controls

| Input | Action |
| --- | --- |
| Mouse | Aim the nose (pitch + yaw) |
| `W` / `S` | Main thrust / reverse |
| `A` / `D` | Strafe left / right |
| `Q` / `E` | Roll |
| `R` / `F` | Thrust up / down |
| `Shift` | Afterburner |
| `Space` | Fire autocannon |
| `X` | Dampeners (kill drift) |
| `C` | Auto-level roll and pitch |
| `Tab` | Cycle target lock |
| `V` | Toggle chase / cockpit camera |
| `M` | Release the mouse cursor |
| `Esc` | Pause · `F5` restart |

A gamepad works too: right stick aims, left stick rolls and strafes, triggers
thrust, `A` fires, bumpers cycle targets.

## How it plays

Flight is Newtonian, not arcade: you build momentum and keep it. The main drive
is weak, the afterburner is strong, and coasting drag is deliberately gentle, so
the fastest way to turn is to keep your nose on the target and let the ship drift
sideways.

Damage splits into shields first, then hull. Shields regenerate after a few
seconds without being hit; hull does not. Ram a planet or a rock at speed and
you will hurt yourself as much as the thing you hit — the momentum is split
between the two bodies.

Six ships fight in a 900 m sphere: you and two allies against three hostiles.
Kills score for the team, and the first team to a higher tally when the
five-minute clock runs out wins. Everyone respawns four seconds after dying.

The arena has small planets with gravity wells strong enough to bend your flight
path into an orbit if you fly too close, and a few of them have moons. Rocks are
destructible: enough sustained fire shatters the smaller ones, and they respawn
elsewhere after a while.

## Layout

```
scripts/
  game_config.gd    tuning table: every balance number in one place
  game_input.gd     builds the whole input map at runtime
  space_ship.gd     flight model, shields/hull, autocannon  (base class)
  player_ship.gd    mouse aim + throttle, cockpit/chase toggle
  ai_ship.gd        patrol → engage → evade → retreat state machine
  laser_bolt.gd     raycast-per-frame projectile (cannot tunnel)
  arena.gd          builds rocks, planets, moons, boundary; spawn selection
  star_body.gd      planet/moon mesh + gravity well
  asteroid.gd       tumbling destructible rock
  camera_rig.gd     chase camera with damped roll and obstacle avoidance
  hud.gd            all 2D readouts, drawn in _draw()
  sfx.gd            synthesises every sound effect at boot
  mesh_factory.gd   noise-displaced rock/planet meshes
  starfield.gd      2600 stars in a single draw call
  main.gd           match lifecycle, spawning, respawns, pause
shaders/
  space_sky.gdshader   procedural nebula + star field + sun
  boundary.gdshader    arena shell: lat/long grid, fresnel rim, danger tint
```

## Tests

Three headless suites. All exit non-zero on failure.

```bash
godot --headless res://tests/input_test.tscn    # 33 checks, real key bindings
godot --headless res://tests/smoke_test.tscn    # 80 checks, full match loop
godot --headless res://tests/ai_gunnery.tscn    # focused AI duel
```

`input_test` pushes real `InputEventKey` / `InputEventMouseMotion` objects
through `Input.parse_input_event()` — the same entry point the OS uses — and
checks that W/S/A/D, Q/E, R/F, Shift, Space, X, C, Tab, V and Esc actually
move the ship, fire the guns, engage the burner and pause the game.

This suite exists because it did not. `smoke_test` drove the game with
`Input.action_press()`, which sets an action directly and bypasses the keyboard
bindings entirely. That proved the controllers *read* actions while saying
nothing about whether any key was *bound* to them — and for a while none were:
see the note on `_add_action` below.

`smoke_test` boots the real main scene and checks flight, boost, dampeners,
shield overflow, hull damage, death, respawn, scoring, AI behaviour, gravity and
asteroid destruction.

`ai_gunnery` is deliberately narrow: one pilot versus one stationary hostile in
an otherwise empty scene. Isolating the duel is what makes aim and lead bugs
obvious instead of hiding them behind a live five-ship dogfight.

## Screenshots

`tools/capture.gd` boots the real scene, drives it with synthetic input, and
writes PNGs. Useful for reviewing visuals without a window:

```bash
godot --rendering-driver opengl3 res://tools/capture.tscn -- res://captures \
  "+shot=cruise,300,1.0,0.0,1,1,0,0,chase,0"
```

Shot spec: `name,frames,thrust,strafe,boost,fire,yaw,pitch,cam,roll[,duel]`.
Appending `duel` parks the player in front of the nearest hostile so the
targeting HUD can be reviewed against a real contact.

## Notes on a few decisions

**Bolts are raycasts, not physics bodies.** Each bolt casts a ray from its
previous position to its next one every physics frame. At 320 m/s a body-based
projectile would tunnel straight through a ship between frames; the ray cannot.

**The AI aims its nose at the lead solution and thrusters separately.** An
earlier version blended "direction I want to travel" into "direction I want to
point", which made ships fly backwards through their own dogfights. Steering
now tracks the target while translation handles the orbit.

**Weapon recoil is tiny.** At the autocannon's ~9 shots/sec, a physically
plausible recoil becomes a continuous shove that measurably pushes a ship out of
its engagement band. The kick is mostly camera punch instead.

**All audio is synthesised.** `sfx.gd` builds short PCM buffers at boot: the
laser is a frequency sweep with noise, explosions layer noise with a sub-drop,
and the engine is a looped drone whose volume and pitch track throttle and
afterburner.

**The input map is built at runtime, but never erased.** `_add_action()` only
creates an action if it is missing. Most actions are declared in two tables (keys
*and* gamepad), and an earlier version erased-and-recreated on every call — so the
second pass silently threw away the keyboard bindings installed by the first.
The result was an input map where every action existed, reported a gamepad axis
as its only event, and responded to nothing on the keyboard. `input_test` exists
to catch that class of bug by counting *keyboard* events specifically, since
"has at least one event" passes even when the only event is a joystick axis.

Registration also happens in `_ready()`, not `_init()`: an autoload's `_init()`
runs before the engine finishes applying `project.godot`, and the settings load
then overwrites the map.

## Tuning

Every balance number lives in `scripts/game_config.gd`. The ones worth touching
first:

- `ARENA_RADIUS` — how big the arena is
- `SPEED_CRUISE` / `SPEED_BOOST` / `DRIFT_DAMPING` — flight feel
- `AI_ENGAGE_BAND_MIN` / `AI_ENGAGE_BAND_MAX` — how close AI fights
- `ai_skill` on `main.tscn` — AI competence, 0.4 (clumsy) to 1.8 (ace)
- `ally_count` / `enemy_count` on `main.tscn` — team sizes

Ship geometry is built from primitives in `scenes/ships/ship_model.tscn`; paint
and engine colours are applied at runtime from the ship's team, so one scene
serves both sides.
