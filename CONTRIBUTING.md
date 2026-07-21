# Working on Busser

Practical guide for anyone picking this up. Read `README.md` first - this file
is about *workflow*, not architecture.

## Setup (once)

1. Download **Godot 4.7.1, standard build** (NOT the .NET/C# build) from
   [godotengine.org](https://godotengine.org/download). It's a single ~180MB
   `.exe` with no installer. Put it wherever you like.
2. Launch it → **Import** → pick this repo's `project.godot` → **Import & Edit**.
3. First open takes a minute while Godot imports the `.glb` models and builds
   `.godot/`. That folder is generated cache - it's gitignored, never commit it.
4. Press **F5**. You should land on the main menu. **Solo Shift** to play.

If the editor throws import errors on first open, close it and reopen once -
Godot occasionally needs a second pass to resolve resource UIDs.

## Day-to-day loop

```bash
git checkout -b feat/short-description   # branch for anything non-trivial
# ... work ...
BUSSER_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn   # verify
git add -A && git commit -m "Add X"
git push -u origin feat/short-description
```

Work on branches, not straight onto `main`. Open a PR even if nobody reviews it
today - it's a readable record of *why* a change happened, and it's how the
other person catches up after time away.

### Commit messages

Present tense, describe the change, one line if it fits:

```
Split dish pit into three standalone stations along the east wall
Controller support: DS4/gamepad bindings, right-stick look, UI focus
```

If the *why* isn't obvious from the subject, add a body paragraph. Future-you
debugging a regression will care a lot about the why.

## Definition of done

Before you commit, all three:

1. **The project imports with no script errors.**
   ```bash
   godot --headless --path . --quit
   ```
   Silence is success. Any `SCRIPT ERROR` / parse error means it's not done.
   **This does not catch everything.** `--quit` only scans resources, so a
   parse error in a script that no imported resource loads (a harness, a scene
   attached late) slips through and shows up as the game hanging instead. The
   soaks below are what actually exercise those.
2. **Both soak harnesses still pass.** There is one per half of the loop.
   ```bash
   # AI half: guests queue, get seated, order, eat, leave
   BUSSER_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn
   # Player half: grab, hand-stack, tub scoop/carry/dump, machine, expo run
   BUSSER_RETURN_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn
   ```
   The first ends with `SOAK FINAL: covers=N walkouts=N -> OK` (if covers stops
   climbing, you've broken seating or the kitchen). The second prints a
   per-check PASS/FAIL table and ends `RETURN SOAK FINAL: OK`, **exiting 1 on
   any failure** so it can gate CI. Run the return soak after touching
   `dish.gd`, `bus_tub.gd`, `busser.gd`, or any station prop.
3. **You actually ran it.** Neither harness can judge *feel*. They prove the
   state machine is intact, not that carrying is fun or that reach angles are
   comfortable. Anything touching movement, camera, or tuning constants must be
   played in-editor before you call it done.

For multiplayer changes, test with two windows: **Debug → Customize Run
Instances → Enable Multiple Instances (2)**, then F5.

## Recipes

### Adding a new player interaction

Follow the authority rule in the README. Short version:

1. Add the action to `project.godot` Input Map (give it a keyboard **and** a
   joypad binding).
2. If the player should be able to rebind it, add it to `Settings.REBINDABLE`.
3. In `busser.gd`, detect the input **only on the authority branch**, and send
   an intent RPC to peer 1 - do not mutate anything locally.
4. Implement the mutation in a `@rpc("any_peer", "call_local", "reliable")`
   function guarded by `if not multiplayer.is_server(): return`.
5. Add the binding to the controls table in `README.md`.

### Adding a new prop

Make it a **standalone scene** under `scenes/props/` with its own script and
`class_name`. It should know nothing about who uses it - `BusTub` doesn't know
what a `Busser` is beyond a hold point. If a prop participates in the dish
economy, it talks to `DishLedger` and `Dish` states, not to other props.

If the prop has static collision that guests must path around, put it in the
`nav_geo` group so the navmesh bake picks it up (see `diner.gd`).

### Adding a HUD readout

Prefer **deriving** the value from data that's already synced over adding new
replication. `GameState.net_earnings()` is the model: it recomputes from the
synced cover count and the dish pool, so it costs zero network traffic and can
never desync. Connect to `GameState.stats_changed` or `DishLedger.changed`
rather than polling in `_process` where you can.

### Adding a sound

1. Drop the file in `assets/audio/` and add an id to `Audio.SOUNDS`.
2. Trigger it from **replicated state**, not from the verb that caused it - a
   dish state transition, a derived count, a flag every peer computes. That way
   it plays correctly on all peers with no networking. See `dish.gd`'s
   `STATE_SOUNDS` for the pattern.
3. Use `Audio.play_3d()` for anything in the world and `Audio.play_ui()` for
   menus. Never create an `AudioStreamPlayer` in gameplay code - the pool exists
   so a dropped stack of plates does not spawn a node per plate.
4. For a continuous sound owned by a prop (machine hum, room tone), use
   `Audio.make_loop_3d()`; it returns a player the prop owns and can stop.

The sounds currently in `assets/audio/` are synthesized placeholders from
`tools/gen_placeholder_audio.py`. Replacing one is a drop-in as long as the
filename stays the same.

### Tuning game feel

Constants live at the top of their owning script and are catalogued in **§9 of
the GDD**. Change them there, then update the ledger. Don't scatter magic
numbers into logic.

## Gotchas that have already bitten us

- **Missing `is_server()` guard.** The single most common bug in this repo.
  Server-only logic that runs on clients causes drift that looks like a physics
  bug and isn't.
- **`carry_load` is pushed by RPC, not the body synchronizer.** The busser's
  synchronizer is client-authoritative, so putting server-owned values on it
  means the client clobbers them. If you add a server-owned player value, push
  it the same way `carry_load` is pushed.
- **Space queries only work inside the physics step.** `intersect_ray` from an
  RPC handler silently misbehaves. See `bus_tub._settle_pending` for the
  defer-to-`_physics_process` pattern.
- **Held items get their collider muted, not disabled.** Muting
  `collision_layer`/`collision_mask` and restoring them is deliberate - see the
  comments in `dish.gd` and `bus_tub.gd`. Don't "simplify" it to `freeze`.
- **Tubs are intentionally non-solid to players.** That's a design decision, not
  a bug - GDD §10 explains the trade-off. Don't remove the collision exceptions.
- **Don't commit `.godot/`.** It's generated. It's gitignored. If it shows up in
  `git status`, something's wrong with your gitignore, not with the ignore rule.

## Where the work is

Both halves of the loop are now covered by harnesses, so the **logic** is
proven. What's left at the MVP gate is **judgement**, which needs a human:

- **Feel tuning.** Reach angles, carry speed, wobble, throw arcs, scoop stack
  height. A harness can tell you a plate reached `AT_PIT`; it cannot tell you
  that grabbing felt sticky. Constants are catalogued in GDD §9.
- **The 2-instance client render.** The lobby's host side is wire-verified and
  the client repaint rides RPC patterns already proven in shipped code, but
  nobody has watched two windows agree. Run two instances and check the crew
  roster, ready-gate, and held-dish visuals from the *client's* side.

After that, GDD §11 has the ordered polish list. Realistically the biggest
presentation gaps right now are **no audio at all** (no files, no
`AudioStreamPlayer` anywhere) and **no first-person hands/arms** - the two
things a viewer notices in the first ten seconds.
