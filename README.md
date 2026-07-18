# BUSSER

First-person co-op restaurant bussing. The kitchen runs itself - you clear the tables and wash the dishes.

An **SMT Games** joint. Godot 4.7, typed GDScript.

## Run it

1. Open Godot 4.7 → Import → select this folder's `project.godot`.
2. F5 to run. **Solo Shift** to play alone.
3. Multiplayer on one PC: **Debug → Customize Run Instances → Enable Multiple Instances (2)**, then F5 - click **Host** in one window, **Join** (blank IP = localhost) in the other.

## Controls

| Input | Action |
|---|---|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse | Look |
| LMB | Grab dish / drop dish (also recaptures the mouse) |
| RMB | Throw held dish (throw hard enough and it *breaks* - permanently) |
| E | Start the dish machine (look at the big box at the pit) |
| Esc | Release mouse |

## The loop (current slice)

Grab dirty plates off tables → carry (or yeet) them onto the steel counter (the pit) → press E on the machine → clean plates appear on the shelf. Get every plate clean before the 4:00 shift clock runs out or you're **86'D**.

## Architecture notes

- **Server-authoritative dishes**: clients send intent RPCs (`_server_grab_or_drop`, `_server_throw`, `_server_interact`) to peer 1; the server mutates dish state; `MultiplayerSynchronizer` replicates position/rotation/state down.
- **Client-authoritative player movement** (MVP simplification - no prediction yet).
- **The dish state machine** (`scenes/props/dish.gd`) is the whole economy: `DIRTY → HELD → AT_PIT → WASHING → CLEAN`, plus `BROKEN` (conserved pool shrinks).
- Autoloads: `Net` (connection lifecycle), `DishLedger` (pool registry/counts), `GameState` (shift clock + verdict).
- Known MVP limitations: late joiners may see stale visuals for a frame; held dishes lag slightly on the holder's own screen (server round-trip); no spray-wash minigame yet.

Design docs live in `Docs/`.
