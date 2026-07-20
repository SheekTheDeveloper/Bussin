# BUSSER - Roadmap

**Owner:** SMT Games
**Updated:** 2026-07-20
**Source of truth for _what_ and _when_.** The GDD (`GDD-Busser.md`) is the
source of truth for _how_ a system works. When they disagree, the GDD wins on
mechanics and this file wins on ordering.

Board mirror: `ROADMAP-miro.csv` in this folder imports straight into Miro
(Miro > Import > CSV). Re-export it whenever this file changes so the board and
the repo do not drift.

---

## Status at a glance

| Half of the loop | Proven by | State |
|---|---|---|
| AI half (guests, seating, kitchen) | `BUSSER_SOAK=1` | ✅ automated |
| Player half (grab, tub, machine, expo) | `BUSSER_RETURN_SOAK=1` | ✅ automated, 23/23 |
| Feel (reach, carry speed, wobble, arcs) | human only | 🔲 **the gate** |
| Audio | nothing exists | 🔲 zero files, zero nodes |
| Character animation / hands | nothing exists | 🔲 zero |

**One-line summary:** the systems are done and provably correct. What is
missing is everything that makes it *feel* and *sound* like a game.

---

## M0 - Close the MVP gate (BLOCKS EVERYTHING)

Only a human can do this. Both harnesses prove the state machine; neither can
judge whether the game is good to play.

- [ ] **Feel playtest, in-editor.** Play a full 5:00 shift solo. Tune against
      GDD §9 constants: `GRAB_RANGE`, `CARRY_SPEED`, `STACK_MAX`, `THROW_FORCE`,
      `BREAK_SPEED`, hold-point offsets.
- [ ] **2-instance client render check.** Two windows, host + join. Verify the
      lobby roster repaints on the *client*, held dishes look right on the
      non-authority peer, and the ready-gate works from both sides.
- [ ] Log every feel change as a constant edit + a GDD §9 ledger update.

**Exit criteria:** a full shift is playable end to end and nobody says "the
grab feels broken." Then, and only then, M1+ opens.

---

## M1 - Audio pass (highest payoff per hour)

Currently **zero** audio: no files, no `AudioStreamPlayer` nodes. This is the
single biggest gap between "systems demo" and "game." Most of the hooks already
exist in code, so this is mostly wiring.

**Already-existing hooks to drive audio from - do not rebuild these:**

| Hook | Where | Drives |
|---|---|---|
| `Busser.stack_load` (1..5) | `busser.gd` | clatter intensity by stack size |
| `KitchenPass` starving flag | `kitchen_pass.gd` | chef barks |
| dry-pass alarm condition | `hud.gd` | stall-alert music layer |
| `GameState.tick` / `shift_ended` | `game_state.gd` | shift-phase music stems |
| `Dish.State.BROKEN` transition | `dish.gd` | shatter |
| `DishMachine.washing` | `dish_machine.gd` | wash loop + finish hiss |

- [ ] **Audio bus layout first** (Master / Music / SFX / Diegetic). `Settings`
      already owns master volume - extend it to per-bus sliders in the same
      pattern, do not invent a second settings path.
- [ ] SFX: grab, drop, stack-clatter (scaled), break/shatter, tub scoop, tub
      set-down, machine loop, machine finish hiss, door chime.
- [ ] Chef barks off the existing starving flag.
- [ ] Diner ambience bed.
- [ ] **Dynamic music stems** reacting to shift state (setup / rush / stall).
      Ambitious - do the static loop first, add stems once it is playing.

**Note:** Godot's `AudioStreamInteractive` (4.3+) handles stem transitions
natively. Use it rather than hand-rolling crossfades.

---

## M2 - Character presence: hands, models, animation

Also zero today: no `AnimationPlayer`, no `AnimationTree`, no first-person arms.
A floating camera with no hands is the second thing a viewer notices.

- [ ] First-person arms/hands visible when carrying (empty / plate stack / tub).
- [ ] Carry poses driven by `stack_load` and `carry_load` (already replicated).
- [ ] Guest + chef idle/walk animation (`guest.gd` currently fakes a code bob).
- [ ] Retarget imported animations; see `Docs/` animation reference.

---

## M3 - Art direction (DECISION REQUIRED FIRST)

**Open decision, see the Decision Log below.** Do not start until it is settled.

If mid-poly is chosen:
- [ ] Bevel pass on metal + ceramic props (cheap, high value, do this regardless)
- [ ] ReflectionProbe in the pit area - **not** SSR (see Decision Log for why)
- [ ] Roughness/metallic material pass; skip SSS on ceramic
- [ ] MultiMesh for high-count props (plates, glasses)
- [ ] Ground-center origins on all props (makes snapping/stacking trivial)

---

## M4 - Feel and collision tuning

Queued behind M0 because the playtest generates this list, rather than guessing
at it now.

- [ ] Carry speed / wobble curve
- [ ] Scoop stack height, throw arcs
- [ ] Spray-wash minigame (GDD §8 "PowerWash-lite")
- [ ] Wipe / place-setting reset step

---

## M5 - Content escalation (post-MVP, GDD §4.5)

**Everything here is on the GDD §7 explicit cut list.** It is good content in
the wrong order - it belongs after the game feels good and makes noise.

- [ ] Walk-in freezer (ice, slip decals)
- [ ] Delivery truck / freight boxes (the Friday 5pm rush)
- [ ] Mop, bucket, wet-floor sign
- [ ] Trash bags / dumpster
- [ ] Casual vs "BusTub Master" mode toggle
- [ ] Player names (crew is peer-IDs only today)

---

## M6 - Studio and marketing

- [ ] SMT Games logo + identity (yellow `#FACC15` / crimson `#DC2626`, already
      the `busser_theme.tres` palette)
- [ ] Short-form clip capture: physics failures and co-op betrayal
- [ ] Steam page: "Overcooked from the other side of the pass"

**Sequencing note:** clips need audio and hands to land. M6 capture work is
gated on M1 and M2, not on calendar.

---

## Decision Log

Decisions get logged here with their cost, so they are not re-litigated.

| # | Decision | Status | Notes |
|---|---|---|---|
| D1 | Mid-poly + shaders, or stay low-poly? | **OPEN** | Mid-poly is a pipeline commitment: 1 `.blend`, few props, zero textures today. Weigh against the low-end-machine principle. |
| D2 | SSR for stainless steel | **REJECTED** | Forward+ only (absent on Compatibility, i.e. low-end/web). Screen-space, so it breaks on off-screen geometry - exactly the plate-stack case. Use a ReflectionProbe. |
| D3 | Subsurface scattering on ceramic | **REJECTED** | Ceramic is not translucent enough to read at first-person gameplay distance. Cost with no visible payoff. |
| D4 | Beveled edges on props | **ACCEPTED** | Nearly free, does most of the perceived-quality work on its own. |
| D5 | MultiMesh for high-count props | **ACCEPTED** | Consistent with the optimization principle. |
| D6 | Repo name `Bussin` vs game name `Busser` | **DEFERRED** | Names still in flux; deliberately left mismatched. |
| D7 | Build §5 escalation content now | **REJECTED** | On the GDD §7 cut list. Revisit at M5. |

---

## Working agreement

- Both harnesses green before any commit (see `CONTRIBUTING.md`).
- Feature work on branches, PRs even when unreviewed.
- A change to mechanics updates the GDD; a change to ordering updates this file.
- New decisions get a row in the Decision Log, with the cost written down.
