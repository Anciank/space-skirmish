# Star Skirmish

A native 3D space combat game in Godot 4. Join Azure squadron in a configurable
Newtonian skirmish with twin autocannons, destructible asteroids, gravity anchors,
and a bounded combat volume. Ships, scenery and sound effects are generated in code.

The art direction is restrained industrial science fiction inspired by EVE Online.
The original AZ-00 corvette has a blunt pressure hull, segmented metal armor,
exposed cannon barrels and feed mechanisms, radiator banks, sensors, and opposing
reaction-control ports. Squadron colors appear on identification bands; both sides
use the same cool drive plasma and warm kinetic tracers. Main-drive plumes follow
forward thrust, and reaction-control jets fire opposite lateral, vertical and reverse
commands. Short local shield ripples, impact ejecta and drifting metal fragments
communicate damage without covering ships in constant glow.

A single warm sun lights ships, rocks and the distant planet consistently. The
planet sits in the sky at astronomical distance, while local airless rubble has
matching collision hulls. Muted dust lanes, sparse fixed stars and a proximity-only
combat boundary replace the bright nebula and visible grid cage. Menus and flight
instruments use graphite panels, fine rules and restrained status colors.
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
| `Page Up` / `Page Down`, mouse wheel | Change scoreboard page while open |

A gamepad works too: right stick aims in all four directions, left stick rolls
and strafes, triggers thrust, `A` fires, `B` brakes, right bumper cycles targets,
Start pauses, and Back opens the scoreboard. Menus support mouse, keyboard and
gamepad focus navigation. Losing application focus pauses a running sortie.

Settings apply during play and persist locally: mouse sensitivity, invert
mouse up/down, invert Q/E roll, hints, master, weapons, engine and music volume, field of view, camera
shake, fullscreen and interface language. Invalid saved values recover to safe
defaults or supported ranges.

Choose **Interface language** in Settings to change menus, flight instruments,
combat messages and debriefs immediately. The selection stays on this device;
changing it during pause preserves the paused battle and menu focus. Languages
are listed by their native names: English, 简体中文 (Simplified Chinese), Español
(Spanish), हिन्दी (Hindi), العربية (Arabic), Português (Brasil), Français
(French), Deutsch (German), 日本語 (Japanese), 한국어 (Korean), Русский (Russian),
and Bahasa Indonesia. Arabic text is shaped and read from right to left, with
stable pilot callsigns and numerical readouts.

The game bundles Noto fonts for Latin, Cyrillic, Chinese, Japanese, Korean,
Arabic and Devanagari, so these languages render without installed system
fonts. Font licenses appear in Credits and in `assets/fonts/`. Translation
catalogues live in `translations/`, keyed by the English source text; missing
entries fall back to English.

## How it plays

Flight is Newtonian, not arcade: you build momentum and keep it. The main drive
is weak, the afterburner is strong, and coasting drag is deliberately gentle, so
the fastest way to turn is to keep your nose on the target and let the ship drift
sideways.

Mouse up/down can pitch through complete turns continuously. Aim turns around
the ship's own axes, so controls keep their screen direction while banked,
inverted, or passing straight up or down. Vertical aim inversion also applies
to the gamepad; Q/E roll inversion is separate and both preferences are saved.

Damage splits into shields first, then hull. Shields regenerate after a few
seconds without being hit; hull does not. Ram a gravity anchor or a rock at speed and
you will hurt yourself as much as the thing you hit — the momentum is split
between the two bodies.

Choose the NPC counts on the command screen: 0–31 allies and 0–32 hostiles, plus
your own ship. The default is 32 versus 32 in a 900 m sphere. Counts are
saved on this device and applied when deploying or restarting a sortie. Choose
zero hostiles for a practice flight; pause and debrief tables scroll to show a
full 64-ship roster.
Kills score for the team; the higher tally when the five-minute clock runs out
wins. Everyone respawns four seconds after dying. Combat, scoring and redeploys
stop at the debrief. Replay creates a fresh roster and clears old projectiles.
Pilot records and projectile credit survive ship replacements.

AI pilots reassess targets by range, enemy aim, recent attacks and remaining
defenses. They keep a lock unless another contact is meaningfully better. In a
fight they match the target's movement, correct their range, and orbit with the
thrusters while tracking the cannon lead point. Close passes and urgent hazards
take priority over shooting. Pilots use the burner for aligned approaches and
breakaways, steer around rocks and other hulls, and brake before the arena edge.

Incoming hostile rounds and recent hits prompt short sideways dodges; harmless,
friendly and expiring rounds do not. Critical defenses cause a retreat, followed
by a return after shield recovery or a time limit. A cooldown prevents repeated
retreats from keeping a damaged pilot out of combat. Cadet, Pilot and Ace change
decision timing, turning speed, aim error and burst pauses. All pilots use the
same flight, shield and projectile rules as the player.

The target panel reports projectile reach and obstructions, and hides the lead
pip while the firing line is blocked. Contact brackets project the complete hull
bounds, including radiator banks and the prow. Radar follows the ship through yaw,
pitch and roll; allies use circles and hostiles use diamonds. Hit, kill, lock,
critical hull, boost, redeployment and debrief cues support the visual feedback.
A quiet original synth score changes its mix between command and combat.

The debris field includes dense gravity anchors that bend your flight path when
you pass close. Nearby companion rocks are airless local obstacles. The distant
planet is a visual backdrop. Smaller asteroids shatter into cold mineral fragments
under sustained fire and respawn elsewhere after a while.
## Layout

```
scripts/
  game_config.gd    tuning table: every balance number in one place
  game_settings.gd  validated preferences, atomic local persistence
  l10n.gd           twelve language catalogues, text shaping and bundled fonts
  game_input.gd     builds the whole input map at runtime
  game_match.gd     clock, scores, kill feed and persistent pilot ledger
  flight_menu.gd    command, handbook, settings, pause and debrief screens
  gunnery.gd        shared intercept solver and ballistic path safety
  ship_visual.gd    cached corvette meshes, livery, drives and reaction-control ports
  space_ship.gd     flight model, shields/hull, autocannon  (base class)
  player_ship.gd    mouse aim + throttle, cockpit/chase toggle
  ai_ship.gd        patrol → engage → evade → retreat state machine
  laser_bolt.gd     raycast-per-frame projectile (cannot tunnel)
  arena.gd          builds debris, gravity anchors and boundary; spawn selection
  star_body.gd      airless gravity-anchor mesh and collision + gravity well
  asteroid.gd       tumbling destructible rock
  camera_rig.gd     smooth chase/cockpit follow, obstacle avoidance and bounded feedback
  hud.gd            all 2D readouts, drawn in _draw()
  sfx.gd            synthesises every sound effect at boot
  mesh_factory.gd   shared procedural surface helpers and tracer materials
  starfield.gd      sparse fixed stars in a single draw call
  main.gd           session state, spawning, respawns, pause and replay
translations/       twelve UTF-8 JSON catalogues with English source keys
assets/fonts/       bundled Noto fonts, source metadata and font licenses
shaders/
  space_sky.gdshader   muted dust lane, distant planet and shared sun direction
  hull_surface.gdshader machined metal finish, panel seams and local impact heat
  rock_surface.gdshader object-space mineral, cracks and crater surface detail
  atmosphere.gdshader  optional thin atmospheric rim
  engine_jet.gdshader  fading boost plumes
  shield.gdshader      brief rim and local hit response
  soft_sprite.gdshader stars, cannon and impact flashes, explosion sparks
  debris_surface.gdshader lit mineral fragments with finite alpha fade
  boundary.gdshader    subtle proximity warning at the combat-volume edge
```

## Tests

Run the complete verification gate from a clean checkout:

```bash
python3 tools/verify.py
```

It imports the project, checks suite scripts before running them, then runs twelve
headless suites at a fixed 60 FPS simulation timestep. It rejects failed
assertions, script errors, engine errors, warnings and resource leaks. Logs are
saved in a temporary directory. Use `--suite round_flow` to run one suite, or
`--godot /path/to/godot` to select an executable.

Suites can also be run individually after importing the project:

```bash
godot --headless --editor --import --quit     # needed on a fresh checkout
godot --headless res://tests/input_test.tscn    # real key bindings
godot --headless res://tests/smoke_test.tscn    # full match loop
godot --headless res://tests/ai_gunnery.tscn    # focused AI duel
godot --headless --fixed-fps 60 res://tests/ai_combat.tscn # tactical decisions and safe flight
godot --headless res://tests/round_flow.tscn    # real menu and round transitions
godot --headless res://tests/localization.tscn # twelve languages, live switching and fonts
godot --headless res://tests/flight_systems.tscn # flight/resource/gunnery regressions
godot --headless res://tests/camera_stability.tscn # smooth movement and firing at 30/60/144 FPS
godot --headless --fixed-fps 60 res://tests/player_gunnery.tscn # aim assistance and real moving-target hits
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

`ai_combat` checks target switching and lock stability, pursuit of a moving
contact, threat-driven dodges and their cooldowns, and firing from the active
cannon along the predicted shot path. Real physics fixtures cover rocks,
friendly hulls and teammates crossing that path. The suite also checks gun
cooldown, obstacle avoidance with continued forward progress, braking before
the boundary, returning from a retreat without immediately restarting it, and
clearing tactical state on respawn. A freed target must stop stale shots and
allow a living hostile to replace the old lock safely.

`round_flow` activates native menu buttons through real Enter/Escape events.
It checks deployment, frozen clock and physics during pause, settings reload
and recovery, repeated respawns, final statistics, draw results, replay and
return to command. NPC-count checks cover keyboard selection, saved counts,
safe numeric limits, the default 32-versus-32 fleet, custom fleets, zero-hostile practice and full-roster
standings scrolling. Test preferences use an isolated file.

`localization` checks every catalogue against the English source keys, formatting
arguments and bundled glyph coverage. It switches all twelve languages through
the real menus and checks canvas bounds, complete wrapped instructions, heading
clearance, translated HUD shaping and existing combat messages. It also checks
settings focus, native language names, stable
callsigns, pause preservation, saved language preferences and invalid-value
recovery. Test preferences use an isolated file.

`camera_stability` checks smooth cruise, boost and turning at 30, 60 and 144 FPS,
continuous Q/E rolls through multiple revolutions at level and nearly vertical
attitudes, simultaneous pitch/yaw/roll, smooth auto-leveling near vertical and
inverted attitudes, rendered hull alignment, steady sustained fire, rigid cockpit attachment,
teleports, camera toggles, respawns and bounded impact feedback. Disabling camera
shake clears the lens immediately; cosmetic feedback cannot steer the guns.

`flight_systems` checks radians and frame-independent mouse aim, complete pitch
loops at 30/60/144 render rates and 60 physics ticks, local controls through poles
and inverted attitudes, signed gamepad events, spawn orientation, shield recovery, booster acceleration and recharge,
spherical containment, physical impact damage, rock surface contacts, clear asteroid respawns,
logical drive/identification feedback, camera
stability under sustained recoil at uncapped frame rates, and projectile credit
after the shooter is freed. `soak_match` advances the entire five-minute battle with normal
physics steps and checks roster validity, finite transforms, bounded effects,
score consistency and the frozen debrief.
For difficulty audits, run `soak_match` with `-- --difficulty=0 --seed=20261002`
(0 Cadet, 1 Pilot, 2 Ace). The log includes shots, hits, damage, deaths and scores.

`audio_mix` checks signal headroom, DC offset, pitch, loop seams, bus isolation,
critical cues under voice pressure, 20 Hz autocannon overlap and engine smoothing
at 30 and 240 FPS. `player_gunnery` checks bounded assistance, unobstructed muzzle
intercepts, friend crossing safety, moving-target hits and consistent firing
cadence at different physics step rates.
`combat_feedback` checks real physics obstructions, weapon reach, moving target
guidance, radar orientation and collision attribution through the main scene.

## Linux release

Use Godot **4.7.2 stable** with its matching official Linux x86_64 export
templates. Presets are tracked; generated builds are ignored. Build and verify:

```bash
python3 tools/build_release.py --native
```

The gate runs all twelve gameplay suites, exports the shipping pack, verifies
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

Add `--fleet32` after the output path to select and save 32 versus 32 through
the command screen. Large fleets also capture the last scoreboard page.

Use `--rendering-method gl_compatibility --rendering-driver opengl3` to review
the compatibility renderer, or `--resolution 800x450` to review the minimum
window size.

Capture close views of both sides of the ship, boost, firing, shield impacts,
three explosion phases, gravity anchors and rocks:

```bash
godot --path . res://tools/visual_review.tscn -- /tmp/star-skirmish-art
```

Review the distant planet, gravity anchors and cold asteroid fragments:

```bash
godot --path . res://tools/environment_review.tscn -- /tmp/star-skirmish-environment
```

Visual review tools force a completed render frame and opt out of focus-loss
pausing for that process. Add `--audio-driver Dummy` before the scene argument
when reviewing images without native audio.

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
previous position to its next one every physics frame. At 620 m/s a body-based
projectile would tunnel straight through a ship between frames; the ray cannot.

**The AI separates gun tracking from maneuvering.** Steering tracks the lead
solution while a velocity controller matches the opponent's movement and
adjusts range with the ship's real thrusters. Predicted collisions or a close
breakaway temporarily turn the hull along its escape route and hold fire.
Threat checks run at the pilot's reaction rate, and dodges and retreats have
cooldowns so they remain brief tactical moves.

**AI fire checks the actual shot path.** The active cannon supplies the origin
for the intercept calculation. Pilots hold fire when the round cannot arrive
within its lifetime, scenery blocks the lead path, or a teammate will cross
the projectile corridor. Burst decisions use elapsed time, and the gun's own
cooldown must allow a shot before that shot is counted against the burst.

**The camera follows the rendered hull.** Physics interpolation smooths ships,
rocks and rounds between simulation ticks. The chase camera carries the ship's
translation and full rotation directly, with its follow offset stored in ship
space. Q/E can roll continuously through any angle without a world-up correction
or camera reversal. Only obstacle clearance eases; the cockpit stays attached
to the hull. Respawns reset interpolation instead of streaking through the
previous location.

**Weapon recoil is tiny.** A shot applies a small velocity impulse and a gently
damped camera movement of at most 3.5 cm. Firing does not shake the view sideways.
Impact feedback stays on the child camera and cannot accumulate in the follow
pose or change the player's firing direction.

**Player guns help with lead near the sight.** A visible hostile's hull or lead
point must be within 4 degrees of the clean camera axis, and the active cannon
must reach the intercept within its 12-degree tracking cone. Assistance respects
cover and teammates crossing the ballistic path. The brighter cyan sight shows
when it is active; rounds do not home after launch. Cannons fire 20 rounds per
second at 620 m/s, with 0.3-degree dispersion and 3 damage per round. Cooldown
remainder is carried across physics steps to preserve the continuous cadence.

**All audio is synthesised.** `sfx.gd` builds short PCM buffers at boot: the
autocannon report layers a short broadband muzzle crack, low body resonance and
mechanical transients at the actual firing cadence; explosions layer noise with a sub-drop,
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
- `AI_TARGET_SWITCH_MARGIN` / `AI_TARGET_SCAN_INTERVAL` — lock stability and target reassessment
- `AI_THREAT_LOOKAHEAD` / `AI_EVADE_COOLDOWN` — threat response and time between dodges
- `AI_NAV_LOOKAHEAD` / `AI_VELOCITY_GAIN` — obstacle planning and pursuit response
- `AI_RETREAT_DURATION` / `AI_RETREAT_COOLDOWN` — breakaway and return timing
- `AI_SKILLS` in `game_settings.gd` — Cadet, Pilot and Ace competence
- `ally_count` / `enemy_count` on `main.tscn` — team sizes

The shared ship scene uses `ship_visual.gd` to build armored hull sections,
drive housings, weapon assemblies and radiator banks. Geometry is cached across ships and redeployments. Team paint
shares immutable materials, while animated engines and shields own their
parameters. Asteroid collision hulls are built from their individual meshes.
