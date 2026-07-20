# BUSSER - Game Design Document (Draft 0.2)

**Studio:** SMT Games (Sunday Monday Tuesday Games)
**Engine:** Godot 4.7.1 (typed GDScript, high-level multiplayer API)
**Genre:** First-person co-op service-chaos sim ("friendslop with a work ethic")
**Players:** 1-4, drop-in co-op, host-based multiplayer
**Elevator pitch:** Overcooked from the *other* side of the pass. The kitchen runs itself. You and your friends are the bussers - clear tables, haul bins, wash dishes, reset the floor - because the restaurant only makes money when guests can sit down and food can go out on clean plates.

> **Draft 0.2 note:** every system below is now reconciled against the shipped
> code. Sections tagged **[AS-BUILT]** describe what runs today; **[VISION]**
> marks the design target the MVP is a slice of. §7 is the live MVP checklist;
> §9 is the constants ledger; §10 tracks known gaps and bugs.

---

## 1. Design Pillars

1. **The restaurant is the machine; you are the lubricant.** The AI kitchen and AI guests run on their own clock. Players never cook and never serve - they remove friction. Every mess you don't clear becomes a bottleneck somewhere else.
2. **Physicality is the comedy.** First-person, physics-driven plates, wobbling bus tubs, tray stacks that want to die. Skill expression = carrying more without dropping it. Failure is funny, visible, and cleanable.
3. **One closed loop, always legible.** A single conserved dish pool cycles through one state machine; players should always be able to answer "why is the restaurant stalling?" by looking around.
4. **Friends first.** Everything is funnier with 4 people. Systems create *collisions of responsibility* (two people reach for the same table, someone hoards the good tub) rather than assigned roles.

## 2. Core Loop (moment to moment)

**[AS-BUILT]** The dish is the unit of flow. One conserved pool of plates moves
through a single state machine (§4.1); guests and the kitchen consume the clean
end, players recover the dirty end:

```
        ┌──────────────────── the kitchen / guest half (AI-driven) ───────────────────┐
   CLEAN ─(player drops on pass)→ AT_PASS ─(order pulls it)→ COOKING ─(cook timer)→ SERVED
     ▲                                                                                  │
     │                                                                          (guest eats)
     │                                                                                  ▼
   WASHING ←(dish machine)── AT_PIT ←(tub dumped at pit)── DIRTY ←──────────── DIRTY on table
        └──────────────────── the busser half (YOU) ─────────────────────────────────┘
                              (+ HELD while in hands, + BROKEN on a hard throw)
```

1. The **AI host** (`GuestManager`) seats parties only at **READY** tables (empty of guests *and* dishes).
2. When a party is fully seated, the **kitchen pass** takes their order and cooks one **CLEAN** plate per guest - but only if clean plates have been stocked on the pass. Starved of plates, the chef flashes red (diegetic alarm).
3. Cooked plates are **SERVED** to seats; guests eat, then leave, dropping **DIRTY** plates on the table. The table is now *messy* and not READY.
4. **Players** clear dirty plates - grab by hand or scoop into a **bus tub** - haul them to the **dish pit**, dump (→ AT_PIT), run the **dish machine** (→ WASHING → CLEAN on the clean counter), then ferry clean plates back to the **pass**.
5. Covers and tips accrue; walkouts burn rating. Hit the walkout limit → **86'D**.

**The stall states (the real antagonists):** no READY tables → guests queue → walkouts; no clean plates at the pass → kitchen backs up, chef yells; dish pit starved → nothing to cook with. **[VISION]** adds: pit overflow, trash/rags, spills/slip hazards.

## 3. The Player Verb Set

| Verb | Detail | MVP status |
|---|---|---|
| Grab / drop / throw | Physics pickup of one dish; drop resets it clean→CLEAN else DIRTY; hard throw (>6 m/s) breaks it. | **[AS-BUILT]** |
| Scoop into tub | Empty-hands grab a tub (two-handed), then grab-aim at a dirty plate to scoop it in (cap 6); slows you, fills your view. | **[AS-BUILT]** |
| Dump tub at pit | Interact at the dirty counter to tip a loaded tub - plates land AT_PIT. | **[AS-BUILT]** |
| Run dish machine | Interact at the machine: AT_PIT plates wash on a timer → CLEAN on the clean counter. | **[AS-BUILT]** |
| Stack in-hand | Multi-plate hand-stacks with growing wobble (greed dial). | **[VISION]** - MVP is single-dish + the tub |
| Wipe / reset | Rag + place-settings step between messy and READY. | **[VISION]** - MVP: clearing all dishes *is* the reset |
| Wash (spray) | PowerWash-lite per-dish scrub before the machine. | **[VISION]** (§8.1) |
| Haul trash / Mop | Dumpster runs, spills, slip hazards. | **[VISION]** - cut from MVP (§7) |
| Yeet (emergent) | Everything is physics; throwing a plate to a friend at the pit is legal and gravity-punished. | **[AS-BUILT]** |

## 4. Systems

### 4.1 Dish Economy (the heartbeat) - [AS-BUILT]
- Finite pool of plates, **conserved** - never spawned, only cycled or **BROKEN** (a broken plate permanently shrinks the pool for the rest of the shift). MVP scene ships **12 plates** (6 start CLEAN at the clean counter).
- Every dish is always in exactly one state. Enum (`dish.gd`):
  `DIRTY, HELD, AT_PIT, WASHING, CLEAN, BROKEN, AT_PASS, COOKING, SERVED`.
- State is **server-authoritative**; clients freeze their local rigid body and receive position/rotation/state via a `MultiplayerSynchronizer`. Counts are derived from replicated state by `DishLedger`, so every peer computes identical numbers with no extra traffic.
- Break rule: a DIRTY or CLEAN plate moving faster than `BREAK_SPEED` (6 m/s) on impact breaks. A CLEAN plate that touches the floor (group `dirties_dishes`) goes DIRTY.

### 4.2 AI Kitchen (black box on purpose) - [AS-BUILT]
- Not simulated cooking - a throughput machine (`KitchenPass`). Players drop CLEAN plates in the pass zone → they become AT_PASS. Each pending order pulls one AT_PASS plate → COOKING for `COOK_TIME` (2.5 s) → SERVED to the ordering guest's seat.
- Chef mesh idle-bobs and flashes red when guests are `WAITING_FOOD` but zero plates are AT_PASS/COOKING - the diegetic "NEED PLATES!" alarm. Purely derived from replicated state.

### 4.3 Guests - [AS-BUILT]
- `GuestManager` (server-only) spawns parties of **1-4** at the door every ~9 s (jittered), up to a **queue of 4** parties. Queued parties have **30 s** of patience; on timeout the whole party walks out and fires a walkout.
- Navmesh pathing: a `NavigationRegion3D` runtime-bakes a navmesh from the level's static colliders (group `nav_geo`, baked server-side in `diner._ready`); each guest drives a `NavigationAgent3D` to a single destination and re-requests its path every 0.4 s, so it routes around tables and self-corrects after a player bump. Final hop to a seat (which sits just inside the radius-eroded mesh) is a short direct approach. Guests replicate via a `MultiplayerSpawner`. (Superseded the old aisle-lane waypoint routing.)
- Seated flow: `QUEUED → seating → WAITING_FOOD → eating → leaving`. When a whole party finishes eating they leave together, the mess stays, and the shift banks `party_size` covers.
- **[VISION]** per-archetype messiness + patience (Business Lunch → Kids Birthday), tip modifiers by turnaround/cleanliness.

### 4.4 Shift Structure & Economy - [AS-BUILT]
- A run = one **shift** of `SHIFT_LENGTH` = **300 s (5 min)** (MVP; tunable). Ends in **SHIFT COMPLETE** at time-up, or **86'D** the moment walkouts reach `walkout_limit` - which is **crew-scaled** (7 solo → 5 at a full crew), set server-side in `diner._apply_crew_difficulty` and synced by RPC so the fail check and the HUD star meter agree.
- **Money is derived, never stored** (`game_state.gd`): `tips_earned = covers × $8.50`; `breakage_fees = broken × $6.00`; `net = tips − fees`. Because covers is synced and broken is derived from dish state, every peer shows identical dollars with no new RPC.
- **[VISION]** a **$500 shift goal** as a win bar (the Figma receipt mockup shows `$342.50 / $500`). Not implemented - the HUD currently shows net earnings as a bare number with nothing to hit. Add the constant back to `game_state.gd` when the goal actually gates something.
- Rating = a 5-star meter that burns one star per walkout; the end-of-shift receipt grades the run (CLEAN / PASSABLE / ROUGH / 86'D).
- **[VISION]** multi-phase shift (setup → lunch → lull → dinner rush → last call → closing checklist, 12-18 min) and progression unlocks (carts, better tubs, second machine, bigger venues).

### 4.5 Escalation / Content Axis - [VISION]
- Restaurants as levels: Diner (tutorial) → Family Restaurant → Buffet (nightmare) → Fine Dining (fragile, white tablecloths) → Banquet Hall (event mode).
- Modifiers: broken dish machine (hand-wash only), short-staffed kitchen, health-inspector audit, rain (muddy footprints).

## 5. Multiplayer Design - [AS-BUILT]

- 1-4 players, **host-authoritative** (host = server) over ENet (`Net` autoload, port 7777). Gameplay code only ever checks `multiplayer.is_server()`; it never touches peers directly.
- Players and guests spawn via `MultiplayerSpawner`; positions/state replicate via `MultiplayerSynchronizer`. **Only the server simulates physics**; clients freeze bodies and follow. Held items are server-driven to hold points, not physics-replicated.
- **No assigned roles** - all players are identical bussers; specialization is social. Player collision ON; no death, only embarrassment (drop everything).
- **Lesson locked (see memory):** never put a server-set value on a client-authoritative `MultiplayerSynchronizer` - RPC it to the owner instead (this bit the tub carry-load once).
- **[AS-BUILT] Lobby / waiting room** (`scenes/ui/lobby.gd`) - HOST SHIFT and JOIN CREW land in a shared **BREAKROOM LOBBY** (solo skips it and drops straight onto the floor). The server owns an authoritative ready-roster (`peer_id -> ready`) and broadcasts it; clients mirror + render it. START SHIFT is host-only and unlocks only when the whole crew is READY, then loads the diner on every peer via `@rpc`. Same path-consistency trick as the autoloads: the lobby is the current scene on every peer, so `/root/Lobby` RPCs line up. This replaces the old "load straight into the diner" flow and the static crew placeholder.
- **[VISION]** late-join between waves, ping wheel, proximity voice, player-count difficulty scaling, GodotSteam.

## 6. Presentation & UI

- **[AS-BUILT]** Low-poly stylized props built via the Blender-MCP pipeline (plate, bus tub, diner table, dish machine w/ driven status lamp). FBK optimization principle applies: many low-end machines, full atmosphere.
- **[AS-BUILT] UI design system** - one shared Godot `Theme` (`ui/theme/busser_theme.tres`) from the Figma system: hard corners (radius 0), slate-900 panels, hazard-yellow primary, white-12% hairline borders; a condensed display face (wordmark/headings) + tracked mono (readout labels), both `SystemFont`-based so no font file ships. Three screens shipped to the mockups:
  - **Breakroom (main menu):** BUSSER wordmark, diegetic nav (CLOCK IN = solo, HOST SHIFT, JOIN CREW, CLOCK OUT), crew placeholder panel.
  - **In-game HUD:** live SHIFT CREW roster + STATIONS dish-flow panel (top-left); SHIFT TRACKER card (clock bar, net earnings / goal, covers, walkout stars); PLATES CARRIED card + WOBBLE meter that rises while hauling a tub; STATUS ALARM when the pass runs dry; dot+tick crosshair.
  - **Shift Report:** torn-receipt end screen - THE GOOD / THE CHAOS columns, star rating, verdict, and the GROSS → −FEE → NET earnings math.
- **[AS-BUILT] Settings & Pause** (see `Docs/Settings-Controls.md`) - a `Settings` autoload persists options + input rebinds to `user://busser_settings.cfg`; one code-built `SettingsPanel` (Audio / Controls / Video / Key Bindings) is shared by the breakroom's SHIFT SETTINGS nav and the in-shift **ON BREAK** pause overlay. Pause is client-local (co-op is server-authoritative → the sim never stops). Full key rebinding preserves controller bindings and resets to shipped defaults.
- **[VISION]** first-person visible hands/arms; more diegetic UI (table state = physical props, patience via guest body language); colored per-player crew status bars; kitchen walla + diner muzak.

## 7. MVP - "One room, one wave, one sink"

> **[VISION → slice]** one small diner room, 6 tables, one dish pit, one kitchen
> pass, one lunch wave, host + 1 client. Player cap stays 4 (§8.3); MVP is
> validated at 2.

**MVP build checklist (live status):**

| # | Requirement | Status |
|---|---|---|
| 1 | First-person controller + physics grab / drop / throw | ✅ done |
| 2 | Conserved dish pool + single state machine (`DishLedger` + `dish.gd`) | ✅ done |
| 3 | Bus-tub two-handed carry (scoop / haul / dump), view-fill + slowdown | ✅ done (carry-attach fix landed, live-confirm pending - §10) |
| 4 | Table lifecycle READY → occupied → messy → cleared → READY | ✅ done (no wipe/reset step - that's [VISION]) |
| 5 | Guest party spawner + queue patience + walkouts | ✅ done |
| 6 | Kitchen throughput stub (plates in → cook timer → food out) | ✅ done |
| 7 | Dish pit: tub dump → machine timer → clean shelf | ✅ done |
| 8 | Host + 1 client over ENet, state-replicated (held items server-driven) | ✅ done (headless-verified) |
| 9 | Shift timer + 86'D fail + end screen (covers/tips/breaks/walkouts) | ✅ done |
| 10 | Shift economy (tips / fees / net / rating) | ✅ done |
| 11 | UI design-system pass (menu / HUD / shift report) | ✅ done |
| + | Settings + pause overlay + key rebinding (post-MVP polish, pulled forward for the demo - §6, `Docs/Settings-Controls.md`) | ✅ done (headless-verified) |
| - | **Live playtest of the RETURN half of the loop** (table → tub → pit → wash → clean → pass) | 🔲 **the remaining MVP gate** (§10) |

**Explicitly NOT in MVP (cut):** stacking-in-hand, wiping/place-settings, spray-wash feel, trash/dumpster, rags, mopping, multiple restaurants, cosmetics, voice, Steam, menu lobby/matchmaking.

## 8. Design Decisions (locked 2026-07-18)

1. **Washing:** satisfaction-lite spray (PowerWash-adjacent) + the pass-through machine as the logistics layer. *MVP ships the machine only; spray is post-MVP.*
2. **Failure:** YES - **86'D** is a full "WASTED"-style slam. Two modes: **Casual** (no-fail score chase, default) and **BusTub Master** (ranked, fail armed). *MVP wires the 86'd fail + report; mode toggle is post-MVP.*
3. **Player cap: 4.**
4. **Breakage:** ON - broken dishes permanently shrink the shift pool. Generous 6 m/s threshold so only genuine yeets break. Sweep-up/mitigation post-MVP.
5. **Name: Busser** (gender-neutral). *86'd* stays as the fail screen.

## 9. As-Built Constants Ledger

| Constant | Value | Where |
|---|---|---|
| Shift length | 300 s | `GameState.SHIFT_LENGTH` |
| Walkout limit (→ 86'd) | crew-scaled: 7 solo → 5 at 3+ (`clampi(8-crew,5,7)`) | `GameState.walkout_limit`, set in `diner._apply_crew_difficulty` |
| Tip per cover | $8.50 | `GameState.TIP_PER_COVER` |
| Breakage fee | $6.00 | `GameState.BREAKAGE_FEE` |
| Shift goal | $500 | **[VISION] not implemented** - see §4.4 |
| Bus tub capacity | 6 | `BusTub.CAPACITY` |
| Hand-stack capacity | 5 plates | `Busser.STACK_MAX` (grab to add, grab-away to set down, throw = top plate) |
| Plate break speed | 6 m/s | `Dish.BREAK_SPEED` |
| Cook time / plate | 2.5 s | `KitchenPass.COOK_TIME` |
| Party size | 1-4 | `GuestManager._spawn_party` |
| Spawn interval | crew-scaled: 14 s solo → ~5.2 s at 4 (×0.72/player, ×0.8-1.2 jitter, 4 s floor) | `GuestManager.BASE_SPAWN_INTERVAL`, `PER_PLAYER_SPEEDUP`, `MIN_SPAWN_INTERVAL` |
| Queue patience | crew-scaled: 45 s solo → 30 s at 4 (−5 s/player) | `GuestManager.BASE_QUEUE_PATIENCE`, `MIN_QUEUE_PATIENCE` |
| Max queued parties | crew-scaled: 3 solo → +1 per extra busser, capped at table count | `GuestManager.BASE_MAX_QUEUE` |
| Dishes in MVP scene | 12 (all start CLEAN on the clean counter) | `diner.tscn`, `Dish.start_state` |
| ENet port / max players | 7777 / 4 | `Net.PORT`, `Net.MAX_PLAYERS` |
| Look sensitivity range | 0.2x - 3.0x (mouse & stick, ×base look consts) | `Settings.*_SENS_MIN/MAX` |
| Options/rebinds store | `user://busser_settings.cfg` | `Settings.CONFIG_PATH` |
| Pause / rebindable actions | `pause` action (Esc / Start) + 9 rebindable actions | `project.godot` `[input]`, `Settings.REBINDABLE` |

## 10. Known Gaps & Bugs (pre-polish)

- **RETURN-HALF VALIDATION (MVP gate):** the forward half (CLEAN→…→DIRTY) is proven by the headless soak harness (`BUSSER_SOAK=1`), but the busser half (DIRTY → tub/hand → AT_PIT → WASHING → CLEAN → pass) has never been driven end-to-end in a live session. This is the one thing standing between "systems complete" and "MVP loop proven." **Needs a human in-editor playtest.**
- **~~BUG - plates fall through a picked-up tub~~ - FIXED in code, live-confirm pending:** root cause was `bus_tub._physics_process` returning early when the tub had no carrier, which stopped it driving its `contents`, so stowed plates were left frozen mid-air on set-down. Fix (in `bus_tub.gd`): only the carrier-follow is gated on `carrier != null`; the nesting loop now runs every server frame whenever `contents` is non-empty (plates ride the tub carried, grounded, or knocked - logically attached via `contents[] ↔ Dish.in_tub`, no reparent so MP synchronizer paths stay intact). Headless-repro-verified; **needs the same in-editor playtest as the return-half gate to sign off live.**
- **No wipe/reset step:** clearing all dishes flips a table straight to READY. Place-settings/rag pass is [VISION].
- **DESIGN - tubs are non-solid to player bodies (intentional):** each local Busser capsule holds a collision exception against every tub (`busser._ready` authority branch + `bus_tub._ready` self-register). Since movement is client-authoritative, only a peer's own capsule runs `move_and_slide`, so this single rule stops carried/dropped tubs from launching or jittering any player on host and clients alike. Trade-off: you walk *through* a resting tub rather than bumping it - acceptable for a bussing sim, and it also stops tubs left in walkways from trapping teammates. Tubs remain solid to walls, dishes, and each other.
- **Crew is peer-IDs only:** no player-name system; the lobby + in-game crew rosters read "YOU / PLAYER <id>". A real name-entry step is [VISION]. (The old "host loads straight into the diner / static crew placeholder" gap is now closed by the lobby - §5.)
- **Lobby - host-side wire-verified, client render live-confirm pending:** a two-process headless test proved the server seeds its roster, sees the client connect, grows the roster, and gates START correctly. The client-side repaint rides RPC patterns already proven in shipped code (`GameState._sync_stats` etc.) but wasn't confirmed by the throwaway harness - fold it into the same 2-instance in-editor playtest as the MVP gate.

## 11. Polish Phase (queued after MVP loop is proven)

Ordered target set once the return-half playtest passes:
0. ~~Settings / pause / key rebinding~~ - ✅ done early for the demo (§6, `Docs/Settings-Controls.md`).
1. ~~Fix the tub-carry plate attachment~~ - ✅ fix landed in `bus_tub.gd`, live-confirm pending (§10).
2. Character models + first-person hands/arms; import + retarget animations.
3. Textures + more meshes/props/assets (Blender-MCP pipeline).
4. Sound pass - grab/drop/break/wash/machine, chef barks, diner ambience, muzak.
5. Collision + feel tuning (carry speed, wobble, scoop stack height, throw arcs).
6. Then: spray-wash feel, wipe/reset step, mode toggle (Casual / BusTub Master), menu lobby.
