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
2. **The soak harness still passes.**
   ```bash
   BUSSER_SOAK=1 godot --headless --path . res://scenes/levels/diner.tscn
   ```
   Ends with `SOAK FINAL: covers=N walkouts=N -> OK`. If it says `FAIL`, or
   covers stops climbing, you've broken the seating/kitchen loop.
3. **You actually ran it.** The soak only exercises the *AI half* (guests,
   seating, cooking). It cannot press a button. Anything touching carrying,
   grabbing, throwing, or washing must be played in-editor before you call it
   done.

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

The **MVP gate** (GDD §7, §10) is a live in-editor playtest of the *return half*
of the loop: table → tub/hand-stack → pit counter → dish machine → clean shelf →
back to the pass. Every system is built and the AI half is proven by the soak
harness, but a human has never driven the busser half end-to-end. Two things
need sign-off in that same session:

- The tub-carry plate-attachment fix (code landed, live-unconfirmed).
- The lobby's client-side roster repaint (host side wire-verified, client render
  live-unconfirmed).

Do that first. It's the difference between "systems complete" and "loop proven,"
and it'll likely surface the next real backlog. After that, GDD §11 has the
ordered polish list - character models and hands/arms is next up.
