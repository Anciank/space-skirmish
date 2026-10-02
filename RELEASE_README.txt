STAR SKIRMISH / @VERSION@

A native 3D space dogfight. Join Azure's three pilots against Crimson in a
five-minute skirmish. Enemy kills score one point; the higher score wins.
Every pilot redeploys after four seconds. Equal scores produce a draw.

PLAY ON LINUX X86_64

Extract the entire archive, then run ./play.sh or launch star-skirmish.x86_64.
Keep the executable and star-skirmish.pck together. Godot is included in the
executable; no editor or separate game installation is required.

The default renderer uses Vulkan. Run ./play-compatibility.sh to use OpenGL 3
on a machine without working Vulkan support. Both launchers work from any
directory. The package targets Linux x86_64 with a working desktop graphics
driver. A 1280 x 720 or larger window is recommended for readable instruments.
Windows and macOS are not included in this release.

FIRST SORTIE

Select Cadet, Pilot or Ace, then Deploy Squadron. Aim at the amber lead pip.
The target panel explains when a contact is out of range or the firing line
is blocked. Radar is aligned to the ship: forward is up, right is right.
Blue circles are allies and red diamonds are enemies.

Your ship retains momentum when you turn. Strafe through a pass and use the
brake to remove drift. Shields recover after 3.2 seconds without a hit; hull
damage stays until redeployment. Break off before the hull fails. Rocks and
planets cause collision damage; gravity wells bend your flight path.

CONTROLS

Mouse: aim                         W / S: thrust / reverse
A / D: strafe                      R / F: vertical thrust
Q / E: roll                        Shift + W: afterburner
Space / left click: fire           X: brake drift
C: auto-level                      Tab: cycle target
V: chase / cockpit camera          M: release mouse cursor
Esc: pause / resume / back         F5: restart sortie
Hold backslash: squadron standings

Gamepad: right stick aim, left stick strafe / roll, triggers thrust,
left stick click boost, A fire, B brake, right bumper target, Start pause,
Back scoreboard. Menus use arrows / D-pad and Enter / A to select.

SETTINGS AND LOCAL DATA

Settings apply immediately and save on this device: mouse sensitivity,
pitch inversion, field of view, hints, shake, fullscreen, and separate master,
weapon / feedback, engine and music volumes. Losing focus pauses flight.
Progress and scores are local to the current sortie. No account is required.

On Linux, preferences and engine logs normally live in:
~/.local/share/godot/app_userdata/Star Skirmish/
(or your XDG_DATA_HOME equivalent).

CREDITS

Original procedural ships, scenery, effects, music and sound are part of the
game. Godot Engine and bundled component notices are in licenses/ and the
in-game Credits screen. build-manifest.json lists the version, build checks
and SHA256 hashes of the package files.
