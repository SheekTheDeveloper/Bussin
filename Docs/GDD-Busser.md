# BUSSER - Game Design Document (Draft 0.1)

**Studio:** SMT Games (Sunday Monday Tuesday Games)
**Engine:** Godot 4.x
**Genre:** First-person co-op service-chaos sim ("friendslop with a work ethic")
**Players:** 1-4, drop-in co-op, host-based multiplayer
**Elevator pitch:** Overcooked from the *other* side of the pass. The kitchen runs itself. You and your friends are the bussers - clear tables, haul bins, wash dishes, reset the floor - because the restaurant only makes money when guests can sit down and food can go out on clean plates.

---

## 1. Design Pillars

1. **The restaurant is the machine; you are the lubricant.** The AI kitchen and AI guests run on their own clock. Players never cook and never serve - they remove friction. Every mess you don't clear becomes a bottleneck somewhere else.
2. **Physicality is the comedy.** First-person, physics-driven plates, wobbling bus tubs, tray stacks that want to die. Skill expression = carrying more without dropping it. Failure is funny, visible, and cleanable.
3. **One closed loop, always legible.** Dirty plate → tub → dish pit → clean plate → kitchen shelf → food goes out → guest eats → dirty plate. Players should always be able to answer "why is the restaurant stalling?" by looking around.
4. **Friends first.** Everything is funnier with 4 people. Systems should create *collisions of responsibility* (two people reach for the same table, someone hoards the good tub) rather than assigned roles.

## 2. Core Loop (moment to moment)

1. **Guests** are seated by an AI host - but only at **clean, set tables**.
2. Guests order; the **AI kitchen** cooks - but only if **clean plates/glasses** are stocked at the pass.
3. AI servers run food out. Guests eat, pay, leave, and leave a **mess**: dirty dishes, glasses, trash, spills, crumbs, the occasional horror (birthday cake incident).
4. **Players**: clear dishes into bus tubs → haul tubs to the dish pit → scrape, rack, wash (sink minigame or pass-through machine) → shelve clean dishes at the pass → wipe/sanitize the table → reset place settings → flip the table's "READY" state.
5. Host seats the next party. Rating and tips accrue. Rush waves escalate.

**The stall states (the game's real antagonists):**
- No clean tables → guests queue at the door → walkouts → rating drop.
- No clean plates at the pass → kitchen backs up → food dies in the window → rating drop.
- Dish pit overflowing → nowhere to put tubs → floor mess spreads.
- Full trash / no clean rags / spill on the floor → slow zones and slip hazards.

## 3. The Player Verb Set

| Verb | Detail |
|---|---|
| Grab / stack | Physics pickup; plates stack in-hand with a growing wobble. Greed is the risk dial. |
| Carry tub / tray | Two-handed carry: bigger capacity, slower, blocks your view at max load. |
| Wipe | Hold-to-wipe surfaces with a rag; rags get dirty, need the rag bucket. |
| Wash | Dish pit: spray-scrape → rack → machine (timed pushes) OR hand-sink (faster per item, occupies a player). |
| Reset | Place settings (plates, roll-ups, glasses) from the service station onto a clean table. |
| Haul | Trash bags to the dumpster (outside! weather! the walk of shame past waiting guests). |
| Mop | Spills and slip hazards. Wet floor sign = temporary mitigation, mop = fix. |
| Yeet (emergent) | Everything is physics. Throwing a plate to your friend at the pit is legal, encouraged, and punished by gravity. |

## 4. Systems

### 4.1 Dish Economy (the heartbeat)
- Finite pool of plates/glasses/silverware per shift (e.g., 40 plates). They are *conserved* - never spawned, only cycled or **broken** (broken dishes shrink the pool until the shift ends; sweep the shards or someone slips).
- Every dish is always in exactly one state: `ON_TABLE_DIRTY → IN_TUB → AT_PIT → RACKED → WASHING → CLEAN_SHELF → ON_TABLE_SET / AT_PASS`. This single state machine drives the whole economy and is the #1 thing to build first.

### 4.2 AI Kitchen (black box on purpose)
- Not simulated cooking - a throughput machine: `orders_in × clean_plate_availability × time = food_out`. Expo window fills with visual dishes. If starved of plates, chefs visibly idle/yell (barks = diegetic alarm).

### 4.3 Guests
- Party generator (size 1-6), patience meters at each stage (waiting to sit, waiting for food, waiting for check). Messiness stat per archetype: Business Lunch (tidy, fast) → Kids Birthday (catastrophic). Leave tips based on table turnaround + cleanliness.

### 4.4 Shift Structure
- A run = one **shift** (12-18 min): pre-open setup → lunch wave → lull (catch-up window, restock) → dinner rush (peak chaos) → last call → closing checklist (full reset of the floor = end-of-run scoring ritual, very satisfying, co-op checklist).
- Score = money (tips + covers) + rating stars; unlocks cosmetics, bigger restaurants, tools (cart, better tubs, second dish machine).

### 4.5 Escalation / Content Axis
- Restaurants as "levels": Diner (tutorial) → Family Restaurant → Buffet (nightmare) → Fine Dining (low volume, high fragility, white tablecloths) → Banquet Hall (event mode).
- Modifiers: broken dish machine (hand-wash only), short-staffed kitchen, health inspector visit (surprise cleanliness audit), rain (muddy footprints).

## 5. Multiplayer Design

- 1-4 players, host-authoritative (host = server). Late join between waves.
- **No assigned roles.** All players are identical bussers; specialization emerges socially.
- Friendslop levers: proximity voice (later), ping wheel, shared physics chaos, player collision ON, revive-free (you can't die - you can only be *embarrassed*: slip animation, drop everything).
- Scale difficulty by player count: guest seating rate and dish pool scale up.

## 6. Presentation

- Low-poly stylized, chunky readable props (FBK optimization principle applies: many low-end machines, full atmosphere - warm lighting, kitchen clatter, muffled diner walla, licensed-adjacent diner muzak).
- First-person with visible hands/arms; carried stacks render in-viewport and physically occlude view at high load.
- Diegetic UI where possible: table state = physical props on it; kitchen stress = chef barks; patience = guests looking around / arms crossed. Minimal HUD: held-item widget, shift clock, money.

## 7. MVP ("One room, one wave, one sink")

> The Storm-graybox equivalent: **one small diner room, 6 tables, one dish pit, one AI kitchen pass, one lunch wave, 2-player co-op.**

Must ship in MVP:
1. First-person controller + physics grab/stack/carry.
2. Dish state machine + conserved dish pool.
3. Table lifecycle: seated → eating → mess spawn → clear → wipe → reset → ready.
4. Guest party spawner with patience + walkouts.
5. Kitchen throughput stub (plates in → food out on a timer).
6. Dish pit: tub dump → rack → machine timer → clean shelf.
7. Host + 1 client over LAN/ENet, synced physics for held items only (everything else state-replicated, not physics-replicated).
8. Shift timer + end screen (covers, tips, breaks, walkouts).

Explicitly NOT in MVP: mopping, trash/dumpster, rags, multiple restaurants, cosmetics, voice, Steam.

## 8. Design Decisions (locked 2026-07-18)

1. **Washing:** satisfaction-lite spray (PowerWash-adjacent scrub feel) + the pass-through machine as the logistics layer. Spray = per-dish satisfaction; machine = throughput planning.
2. **Failure:** YES - getting **86'D** is a full GTA-"WASTED"-style screen slam. Two modes: **Casual** (no-fail score chase, friendslop default) and **BusTub Master** (ranked shifts, fail states armed).
3. **Player cap: 4.**
4. **Breakage (MVP call):** breakage ON - broken dishes permanently shrink the shift's dish pool. Generous break threshold so only genuine yeets are punished; sweep-up and mitigation systems post-MVP.
5. **Name: Busser** (gender-neutral, unlike Busboy). *86'd* lives on as the fail screen.
