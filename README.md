# Star Skirmish

A native 3D space combat game in Godot 4. Join Azure squadron in a three-on-three
Newtonian dogfight, with twin autocannons, destructible asteroids, gravity wells,
and a bounded arena. Ships, scenery and sound effects are generated in code.
The interceptor has swept wings, a faceted canopy and separate team paint.
Boost plumes, cannon flashes, local shield impacts and fading explosion
fragments provide combat feedback; the scenery includes craters, irregular
rocks and thin atmospheric rims.

The command screen introduces the mission and offers Cadet, Pilot and Ace
difficulty. The flight handbook explains controls and tactics. Pause includes
live squadron standings, settings, restart and return to command. Every round
ends in a debrief with team scores, kills, deaths, effective damage and your hit
rate; equal scores produce a draw.

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
| `Space` / Left click | Fire autocannon |
| `X` | Dampeners (kill drift) |
| `C` | Auto-level roll and pitch |
| `Tab` | Cycle target lock |
| `V` | Toggle chase / cockpit camera |
| `M` | Release the mouse cursor |
| `Esc` | Pause / resume; return from handbook or settings |
| `F5` | Restart the current sortie |
| Hold `\` | Live scoreboard |

A gamepad works too: right stick aims in all four directions, left stick rolls
and strafes, triggers thrust, `A` fires, `B` brakes, right bumper cycles targets,
Start pauses, and Back opens the scoreboard. Menus support mouse, keyboard and
gamepad focus navigation. Losing application focus pauses a running sortie.

Settings apply during play and persist locally: mouse sensitivity, invert
pitch, hints, master, weapons, engine and music volume, field of view, camera shake and fullscreen. Invalid
saved values recover to safe defaults or supported ranges.

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
Kills score for the team; the higher tally when the five-minute clock runs out
wins. Everyone respawns four seconds after dying. Combat, scoring and redeploys
stop at the debrief. Replay creates a fresh roster and clears old projectiles.
Pilot records and projectile credit survive ship replacements.

The target panel reports projectile reach and obstructions, and hides the lead
pip while the firing line is blocked. Radar follows the ship through yaw,
pitch and roll; allies use circles and hostiles use diamonds. Hit, kill, lock,
critical hull, boost, redeployment and debrief cues support the visual feedback.
A quiet original synth score changes its mix between command and combat.

The arena has small planets with gravity wells strong enough to bend your flight
path into an orbit if you fly too close, and a few of them have moons. Rocks are
destructible: enough sustained fire shatters the smaller ones, and they respawn
elsewhere after a while.

## Layout

```
scripts/
  game_config.gd    tuning table: every balance number in one place
  game_settings.gd  validated preferences, atomic local persistence
  game_input.gd     builds the whole input map at runtime
  game_match.gd     clock, scores, kill feed and persistent pilot ledger
  flight_menu.gd    command, handbook, settings, pause and debrief screens
  gunnery.gd        shared intercept solver with inherited bolt velocity
  ship_visual.gd    cached interceptor meshes, livery and combat feedback
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
  main.gd           session state, spawning, respawns, pause and replay
shaders/
  space_sky.gdshader   static dust clouds and distant sun
  rock_surface.gdshader object-space rock, moon and planet surface detail
  atmosphere.gdshader  thin atmosphere and explosion shock fronts
  engine_jet.gdshader  fading boost plumes
  shield.gdshader      brief rim and local hit response
  soft_sprite.gdshader stars, cannon and impact flashes, explosion sparks
  boundary.gdshader    arena shell: lat/long grid, fresnel rim, danger tint
```

## Tests

Run the complete verification gate from a clean checkout:

```bash
python3 tools/verify.py
```

It imports the project, checks suite scripts before running them, then runs eight
headless suites at a fixed 60 FPS simulation timestep. It rejects failed
assertions, script errors, engine errors, warnings and resource leaks. Logs are
saved in a temporary directory. Use `--suite round_flow` to run one suite, or
`--godot /path/to/godot` to select an executable.

Suites can also be run individually after importing the project:

```bash
godot --headless --editor --import --quit     # needed on a fresh checkout
godot --headless res://tests/input_test.tscn    # 35 checks, real key bindings
godot --headless res://tests/smoke_test.tscn    # 80 checks, full match loop
godot --headless res://tests/ai_gunnery.tscn    # focused AI duel
godot --headless res://tests/round_flow.tscn    # real menu and round transitions
godot --headless res://tests/flight_systems.tscn # flight/resource/gunnery regressions
godot --headless res://tests/audio_mix.tscn # signal quality, mixing and voice pressure
godot --headless res://tests/combat_feedback.tscn # reach, occlusion, radar and death causes
godot --headless --fixed-fps 60 res://tests/soak_match.tscn # full five-minute round
```

`input_test` pushes real `InputEventKey` / `InputEventMouseMotion` objects
through `Input.parse_input_event()` — the same entry point the OS uses — and
checks that W/S/A/D, Q/E, R/F, Shift, Space, X, C, Tab, V and Esc actually
move the ship, fire the guns, engage the burner, pause and resume the game.

Physical input checks also verify keyboard bindings, which direct
`Input.action_press()` calls bypass. Both paths are covered.

`smoke_test` boots the real main scene and checks flight, boost, dampeners,
shield overflow, hull damage, death, respawn, scoring, AI behaviour, gravity and
asteroid destruction.

`ai_gunnery` isolates a stationary duel and an 80 m/s crossing target. It checks
banking without deflecting the nose, bounded angular speed, firing against the
lead point, projectile reach and actual interceptions. This catches tracking
failures that a stationary target alone can hide. It also checks the hull
retreat threshold, immediate breakaway, stable retreat and boost release when
shields recover.

`round_flow` activates native menu buttons through real Enter/Escape events.
It checks deployment, frozen clock and physics during pause, settings reload
and recovery, repeated respawns, final statistics, draw results, replay and
return to command. Test preferences use an isolated file.

`flight_systems` checks radians and frame-independent mouse aim, signed gamepad
events, spawn orientation, shield recovery, booster acceleration and recharge,
spherical containment, physical impact damage, rock surface contacts, camera
stability under sustained recoil at uncapped frame rates, and projectile credit
after the shooter is freed. `soak_match` advances the entire five-minute battle with normal
physics steps and checks roster validity, finite transforms, bounded effects,
score consistency and the frozen debrief.
For difficulty audits, run `soak_match` with `-- --difficulty=0 --seed=20261002`
(0 Cadet, 1 Pilot, 2 Ace). The log includes shots, hits, damage, deaths and scores.

`audio_mix` checks signal headroom, DC offset, pitch, loop seams, bus isolation,
critical cues under voice pressure and engine smoothing at 30 and 240 FPS.
`combat_feedback` checks real physics obstructions, weapon reach, moving target
guidance, radar orientation and collision attribution through the main scene.

## Linux release

Use Godot **4.7.2 stable** with its matching official Linux x86_64 export
templates. Presets are tracked; generated builds are ignored. Build and verify:

```bash
python3 tools/build_release.py --native
```

The gate runs all eight gameplay suites, exports the shipping pack, verifies
every packed resource checksum and excludes tests, tools and captures. A
separate QA pack drives the release template through menu, settings, flight,
pause, scoring, debrief, replay and quit; the builder verifies that its runtime
and game resource payloads match the shipping package. `--native` also drives
the shipping executable with native X11 keyboard events, records
screenshots in both renderers and checks a clean exit. Omit it for a headless
build; the manifest records which checks ran. Native checks require X11.

Successful builds create `dist/star-skirmish-<version>-linux-x86_64/`, a tar.gz
archive and SHA256 checksum. The folder includes the executable, game pack,
launchers for Vulkan and OpenGL, player instructions, engine notices and a
manifest. An earlier candidate is replaced only after the new build passes.
Extract the full archive and run `play.sh`; the editor is not required.

The tested release target is Linux x86_64. Other operating systems require
their own export and native validation before being advertised as supported.

## Screenshots

`tools/capture.gd` boots the real scene, drives it with synthetic input, and
writes PNGs from the native rendering window:

```bash
godot --path . res://tools/capture.tscn -- res://captures \
  "+shot=cruise,300,1.0,0.0,1,1,0,0,chase,0"
```

Shot spec: `name,frames,thrust,strafe,boost,fire,yaw,pitch,cam,roll[,duel]`.
Appending `duel` parks the player in front of the nearest hostile so the
targeting HUD can be reviewed against a real contact.

Capture command, handbook, settings, flight, scoreboard, death, redeployment,
pause, credits, victory and draw
with the configured renderer:

```bash
godot --path . res://tools/menu_capture.tscn -- /tmp/star-skirmish-review
```

Use `--rendering-method gl_compatibility --rendering-driver opengl3` to review
the compatibility renderer, or `--resolution 800x450` to review the minimum
window size.

Capture close views of both sides of the ship, boost, firing, shield impacts,
three explosion phases, planets, moons and rocks:

```bash
godot --path . res://tools/visual_review.tscn -- /tmp/star-skirmish-art
```

Measure the native six-ship battle with a two-second warmup and ten-second
sample. The tool disables VSync for that process and writes JSON plus the final
battle frame. The report includes rendered
frame percentiles, GPU and CPU render times, physical resolution, memory,
draw calls and projectile counts:

```bash
godot --path . res://tools/performance_review.tscn -- /tmp/star-skirmish-performance.json
```

Use the renderer switches above to compare Forward+ and Compatibility on the
same hardware. Frame times depend on the machine, renderer, resolution and
battle; this short sample complements the full gameplay soak.

Record the actual sound mix and save its source WAV clips:

```bash
mkdir -p /tmp/star-skirmish-audio
godot --path . --fixed-fps 60 --write-movie /tmp/star-skirmish-audio/review.avi \
  res://tools/audio_review.tscn -- /tmp/star-skirmish-audio
```

The review uses the real game for command, weapons, boost, shield and hull
impacts, critical alerts, pause, death, redeployment and victory. AVI includes
uncompressed mixed audio; a `.png` output creates a frame sequence plus WAV.

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
afterburner. Music and engine loops retain continuous boundaries; gain changes
use elapsed time. World, cockpit and UI cues use separate voice pools with
priority protection. Four mix buses feed a limiter on Master.

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
- `AI_SKILLS` in `game_settings.gd` — Cadet, Pilot and Ace competence
- `ally_count` / `enemy_count` on `main.tscn` — team sizes

The shared ship scene uses `ship_visual.gd` to build tapered hull sections and
swept panels. Geometry is cached across ships and redeployments. Team paint
shares immutable materials, while animated engines and shields own their
parameters. Asteroid collision hulls are built from their individual meshes.
