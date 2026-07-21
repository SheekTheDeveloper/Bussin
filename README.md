# BUSSER

First-person co-op restaurant bussing. The kitchen runs itself - you clear the tables and wash the dishes.

An **SMT Games** joint. Godot 4.7, typed GDScript.

## Run it

1. Open Godot 4.7 → Import → select this folder's `project.godot`.
2. F5 to run. **Solo Shift** to play alone.
3. Multiplayer on one PC: **Debug → Customize Run Instances → Enable Multiple Instances (2)**, then F5 - **HOST SHIFT** in one window, **JOIN CREW** (blank IP = localhost) in the other. Both land in the **BREAKROOM LOBBY**; everyone **READY UP**, then the host hits **START SHIFT** to load the diner on both. (Solo skips the lobby.)

## Controls

| Keyboard / Mouse | Gamepad     | Action                                                                                                                       |
| ---------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| WASD             | Left stick  | Move                                                                                                                         |
| Shift            | L3          | Sprint (not while hauling a tub)                                                                                             |
| Space            | Cross       | Jump                                                                                                                         |
| Mouse            | Right stick | Look                                                                                                                         |
| LMB              | R1          | Grab / drop - stack plates by hand, scoop dirties into a carried tub, or set the tub down (empty click recaptures the mouse) |
| RMB              | L1          | Throw the top plate - **tap** to lob a catchable pass, **hold** to wind up a yeet that shatters on impact |
| E                | Square      | Interact - start the dish machine, dump a loaded tub at the pit                                                              |
| Esc              | Start       | Pause ("ON BREAK") - resume, settings, or clock out                                                                          |

All key/mouse bindings, look sensitivity, invert-Y, master volume, and fullscreen live under **SHIFT SETTINGS** (in the breakroom menu or the pause overlay). Everything persists to `user://busser_settings.cfg`.

## The loop (current slice)

The diner runs itself; you keep plates moving through it. One **conserved pool
of plates** cycles forever, and both halves of the loop need you:

```plain
  AI half:   guests queue at the door → seated at a READY table → kitchen pulls
             a CLEAN plate off the pass → cooks it → serves it → they eat & leave
  Your half: dirty plates left behind → bus them (hand-stack or bus tub) → pit
             counter → dish machine → clean shelf → run them back to the pass
```

A table is only **READY** when it has no party _and_ no dishes on it - so an
unbussed table blocks seating, the queue backs up, and parties start walking
out. If the pass runs dry the chef flashes red and nothing gets served.

**The shift is 5:00 long.** You don't win by cleaning everything - you win by
_surviving the clock_. Seating covers earns tips ($8.50/cover); smashing plates
costs you ($6.00 each). Hit the walkout limit and you're **86'D** before the
clock runs out.

The walkout limit is **crew-scaled**: solo gets 7, a full crew of 4 gets the
tight 5. Guest pressure scales the same way (`GuestManager`), so the shift stays
winnable at any headcount instead of being impossible solo or trivial with four.

## Architecture notes

- **Server-authoritative dishes**: clients send intent RPCs (`_server_grab_or_drop`, `_server_throw`, `_server_interact`) to peer 1; the server mutates dish state; `MultiplayerSynchronizer` replicates position/rotation/state down.
- **Client-authoritative player movement** (MVP simplification - no prediction yet).
- **The dish state machine** (`scenes/props/dish.gd`) is the whole economy. One conserved pool, nine states, one cycle:

  ```plain
  CLEAN → AT_PASS → COOKING → SERVED → DIRTY → AT_PIT → WASHING → CLEAN
  ```

  plus `HELD` (in a busser's hands or tub) and `BROKEN` (the only exit - the pool permanently shrinks). Read this enum first: almost every other system is just a query over it. The HUD counts it, the chef's alarm reads it, and the shift's money is derived from it.

- **Derived state over replicated state.** Money is never stored or synced - `net_earnings()` recomputes it from the synced cover count and the `BROKEN` tally, so every peer arrives at the same dollars with zero extra network traffic. Prefer this pattern when adding readouts.
- Autoloads: `Net` (connection lifecycle), `DishLedger` (pool registry/counts), `GameState` (shift clock + verdict), `Settings` (persistent options + input rebinds), `Audio` (pooled sound playback).
- **Audio needs no new RPCs.** Sounds are derived from already-replicated state: a dish transitioning to `BROKEN` plays the shatter on every peer independently, the wash hum follows `DishLedger.count(WASHING)`, and the chef bark follows the same starving flag that turns him red. If you reach for a "play sound" RPC, replicate the state instead.
- **Options/pause** are client-local: co-op is server-authoritative, so pausing never stops the sim - it just frees the cursor. The `SettingsPanel` overlay is one code-built component shared by the breakroom menu and the pause menu. See `Docs/Settings-Controls.md`.
- Known MVP limitations: late joiners may see stale visuals for a frame; held dishes lag slightly on the holder's own screen (server round-trip); no spray-wash minigame yet.

## Repo map

```plain
scripts/autoload/     Globals, always loaded (see project.godot [autoload])
  net.gd              Connection lifecycle - host/join/solo, scene switching
  dish_ledger.gd      Registry of every Dish; count(state) is the query API
  game_state.gd       Shift clock, covers, walkouts, derived money
  settings.gd         Persistent options + input rebinds (user://busser_settings.cfg)
  audio.gd            Pooled SFX playback, bus routing, sound library
scripts/
  guest_manager.gd    Server-side host stand: spawn → queue → seat → walkout
  return_soak.gd      Headless test of the player half (BUSSER_RETURN_SOAK=1)
scenes/actors/
  busser.gd           The player. Client-auth movement, server-auth interaction
  guest.gd            AI diner. Server drives it; clients animate a bob locally
scenes/props/         Dish, BusTub, DinerTable, KitchenPass, DishMachine, counters
scenes/levels/        diner.gd - spawns players, bakes the navmesh, scales difficulty
scenes/ui/            main_menu, lobby, hud, pause_menu, settings_panel
ui/theme/             Shared Godot theme resource (see Docs/DesignSystem-Busser.md)
assets/               .blend source + exported .glb models
  audio/              PLACEHOLDER sounds (regenerate: tools/gen_placeholder_audio.py)
default_bus_layout.tres  Master / Music / SFX / Ambience buses
Docs/                 GDD, design system, controls, and a Godot primer
```

## Start here (reading order)

If you've never opened this project, read in this order - each one makes the
next one make sense:

1. **`Docs/Godot-For-Unity-Unreal-Devs.md`** - if Godot is new to you. Nodes vs
   GameObjects, scenes vs prefabs, autoloads vs singletons.
2. **`scenes/props/dish.gd`** - the state machine everything else revolves around.
3. **`scripts/autoload/game_state.gd`** - how a shift is scored and lost.
4. **`scripts/guest_manager.gd`** - where demand comes from and why tables jam.
5. **`scenes/actors/busser.gd`** - the player verbs, and the RPC pattern below.
6. **`Docs/GDD-Busser.md`** - the full design. Sections are tagged **[AS-BUILT]**
   (runs today) vs **[VISION]** (the target). Trust the code over the GDD when
   they disagree, and fix the GDD when you find drift.

## The one rule: who is allowed to change what

This is the thing to get right before writing any gameplay code. Get it wrong
and bugs show up as desync, which is miserable to debug.

- **Movement is client-authoritative.** Your own busser simulates locally and a
  `MultiplayerSynchronizer` streams the result out. It feels responsive; it's
  also trivially cheatable, which is fine for a co-op game with friends.
- **Everything else is server-authoritative.** The client never mutates a dish,
  tub, table, or guest directly. It sends an _intent_ RPC to peer 1
  (`_server_grab_or_drop`, `_server_throw`, `_server_interact`); the server
  validates, mutates, and the change replicates back down.

So when you add a new interaction, the shape is always:

```gdscript
# On the owning client: detect input, send intent. Do NOT mutate.
if Input.is_action_just_pressed("my_action"):
    _server_my_action.rpc_id(1, some_id)

# On the server: validate, then mutate. This is the only place truth changes.
@rpc("any_peer", "call_local", "reliable")
func _server_my_action(some_id: int) -> void:
    if not multiplayer.is_server():
        return
    ...
```

Guard every server function with `if not multiplayer.is_server(): return`. A
missing guard is the single most common bug in this codebase's history.

## Testing without a second machine

- **Two windows on one PC:** Debug → Customize Run Instances → Enable Multiple
  Instances (2). See the run instructions at the top.
- **Headless harnesses:** two automated runs, one per half of the loop. Both
  boot the diner with no window and are completely inert unless their env var
  is set.

  ```bash
  # AI half - guests queue, seat, order, eat, leave (~75s of simulated service)
  BUSSER_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn

  # Player half - grab, hand-stack, tub scoop/carry/dump, machine, expo run
  BUSSER_RETURN_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn
  ```

  The guest soak (in `guest_manager.gd`) prints telemetry and ends with
  `SOAK FINAL: covers=N walkouts=N -> OK`. The return soak (in
  `scripts/return_soak.gd`) drives a real `Busser` through the same server
  entry points a client's intent RPCs land on, prints a per-check PASS/FAIL
  table, ends `RETURN SOAK FINAL: OK`, and **exits 1 on any failure** so it can
  gate CI.

  Neither can judge *feel*. They prove the state machine is intact, not that
  the game is fun to play.

## Conventions

- **Typed GDScript everywhere.** `var x := 0`, `func f(a: int) -> void:`.
  Types catch the class of error that otherwise only shows up at runtime, in a
  build, in front of someone.
- **Comment the _why_, not the _what_.** The existing comments explain why a
  collider gets muted while carried or why arrival is measured in straight-line
  distance instead of along the navmesh. Match that. Don't write `# add one to i`.
- **Tune with named constants at the top of the file** (`WALK_SPEED`,
  `COOK_TIME`, `CAPACITY`), never magic numbers buried in logic. The design
  constants are also catalogued in §9 of the GDD.
- **Props are standalone scenes.** A `BusTub` knows nothing about who carries it.
  Keep it that way - it's how we swap in skins and upgrades later.
- **Don't leave dead code for the next person to trip over.** Delete it; git
  remembers. If something is deliberately unfinished, say so in a comment.

## Known limitations (deliberate, not bugs to "fix" blindly)

- Late joiners can see stale visuals for a frame.
- Held dishes lag slightly on the holder's own screen - server round-trip, no
  client-side prediction yet.
- No spray-wash minigame; the dish machine is a timer.
- Player movement has no reconciliation, so a laggy client can drift.

## Contributing

Setup, branch/commit workflow, definition of done, recipes for common changes,
and the gotchas that have already bitten us: **[`CONTRIBUTING.md`](CONTRIBUTING.md)**.

## Roadmap

`Docs/ROADMAP.md` is the source of truth for **what and when** (the GDD owns
**how**). It carries the milestone list, the current gate, and a Decision Log
recording what was accepted or rejected and why, so choices are not
re-litigated. `Docs/ROADMAP-miro.csv` is the same board as an importable CSV
(Miro > Import > CSV).

Design docs live in `Docs/`.
