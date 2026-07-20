# Settings, Pause & Key Rebinding

How Busser's options, pause overlay, and input rebinding fit together. All three
were added in the pre-presentation polish pass and share one persistence layer.

## At a glance

| Piece | File | Type |
|---|---|---|
| Persistence + apply + rebind logic | `scripts/autoload/settings.gd` | Autoload `Settings` |
| Shared options overlay | `scenes/ui/settings_panel.gd` | `class_name SettingsPanel extends Control` (code-built) |
| In-shift pause overlay | `scenes/ui/pause_menu.gd` | `CanvasLayer` in `diner.tscn` |
| Breakroom entry point | `scenes/ui/main_menu.gd` → `SHIFT SETTINGS` nav | - |
| Config file | `user://busser_settings.cfg` | `ConfigFile` |

The UI is built in code (no `.tscn`) so `SettingsPanel` is a single drop-in
component both the menu and the pause overlay instance the same way:

```gdscript
var s := SettingsPanel.new()
s.closed.connect(_on_settings_closed)
add_child(s)
```

## `Settings` autoload

Registered before the first scene, so options are applied on boot and gameplay
can read the plain properties directly:

- `master_volume` - applied to audio bus 0 (`linear_to_db`, muted at 0).
- `mouse_sensitivity` / `stick_sensitivity` - **multipliers** over the busser's
  base look constants (`MOUSE_SENSITIVITY`, `STICK_LOOK_SPEED`). `1.0` = stock
  feel; UI range `0.2x .. 3.0x`.
- `invert_y` - `look_pitch_sign()` returns `-1.0`/`+1.0`; `busser.gd` multiplies
  its pitch delta by it for both mouse and right stick.
- `fullscreen` - `DisplayServer` window mode (guarded off under headless).

Mutate through the setters (`set_master_volume`, `set_mouse_sensitivity`, …).
Each **applies + saves + emits `changed`**, so any open panel/HUD can react live.

### Persistence rules

- Missing config on first launch → defaults are kept (no error).
- Keybinds are only written when they **diverge from the shipped default**, so a
  future change to a default binding still reaches existing players.
- Values are clamped on load, so a hand-edited/corrupt config can't break input.

## Key rebinding

Rebindable actions are declared once in `Settings.REBINDABLE` (action id +
display label): movement, jump, sprint, grab, throw, interact, pause. Look axes
stay fixed (mouse + right stick).

- **Defaults** are snapshotted from the project's `InputMap` on boot, *before*
  any override is applied, so **Reset to Default** always restores the shipped
  bindings.
- A rebind replaces only the **keyboard/mouse** half of an action's events and
  leaves any joypad binding intact - rebinding a key never kills controller
  support.
- Capture flow (`SettingsPanel`): press a bind button → it listens in `_input`
  for the next key/mouse press → `Settings.rebind(action, event)`. **Esc cancels**
  the capture without changing anything.
- Overrides are stored as full `InputEvent` objects in the `[keybinds]` section
  of the config (same text format the engine uses).

## Pause overlay ("ON BREAK")

`pause_menu.gd` lives in `diner.tscn` above the HUD (`layer = 10`) and is
**client-local only**. Co-op is server-authoritative, so pausing does **not**
stop the sim - it frees the cursor and offers Resume / Settings / Return to
Breakroom / Clock Out.

- Toggled by the `pause` action (**Esc** / gamepad **Start**), added to
  `project.godot`. `busser.gd` no longer frees the mouse on Esc - the pause menu
  owns the cursor now and recaptures it on resume (only for a live local busser).
- No mid-report pausing: once `GameState.running` is false, the shift-report card
  owns input.
- Opening settings from pause reuses the same `SettingsPanel`; Esc backs out one
  layer at a time (settings → pause → floor).

## Verifying headlessly

The whole stack is verifiable without the editor:

```sh
# compile + class registration
godot --headless --import

# core-loop regression (unaffected by these systems)
BUSSER_SOAK=1 godot --headless res://scenes/levels/diner.tscn
```

The UI panels build their trees in `_ready`, so instantiating them as a run
scene surfaces any construction error. Note: `DisplayServer` key-label lookup and
fullscreen are guarded under headless (unsupported there), so labels fall back to
the raw physical keycode and video changes are skipped.

## Extending

- **New option:** add a default const + a live property + a setter in
  `settings.gd`, persist it in `save()`/`load_all()`, then add one
  `_slider_row`/`_toggle_row` in `settings_panel.gd`.
- **New rebindable action:** add it to `project.godot` `[input]` and to
  `Settings.REBINDABLE` - capture, persistence, reset, and the UI row all follow
  from the list.
