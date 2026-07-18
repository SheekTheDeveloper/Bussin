# Godot 4 for Unity/Unreal Developers - Busser Field Guide

Written for someone fluent in C#/Unity and C++/UE. Godot 4.x (use latest stable 4.x).

## 1. The mental model swap

| You know | Godot equivalent | The catch |
|---|---|---|
| GameObject + Components / Actor + Components | **Node** - but a node IS a single behavior. You compose by building a **tree of nodes** | There's no "add component"; you add child nodes. A "player" is a `CharacterBody3D` with a `Camera3D`, `CollisionShape3D`, `AnimationPlayer` etc. as children |
| Prefab / Blueprint class | **Scene (.tscn)** - any node tree saved to disk, instanceable and nestable | Scenes-within-scenes is THE core pattern. A table, a plate, a guest - each is a scene |
| MonoBehaviour lifecycle (`Awake/Start/Update`) | `_init` / `_enter_tree` / `_ready` / `_process(delta)` / `_physics_process(delta)` | `_ready` fires children-first (bottom-up) - opposite intuition from Awake ordering |
| UnityEvent / delegates / UE delegates | **Signals** - first-class, declared on nodes, connected in editor or code | Idiomatic Godot is signal-heavy: children emit up, parents call down ("call down, signal up") |
| ScriptableObject / DataAsset | **Resource (.tres)** - custom classes extending `Resource`, editable in inspector | Perfect for our dish types, guest archetypes, shift configs. Shared by reference like SOs |
| Singleton / GameInstance / subsystems | **Autoload** - a scene/script registered in Project Settings, alive for the whole game | Our `GameState`, `NetworkManager`, `DishLedger` live here |
| CharacterController / CharacterMovementComponent | `CharacterBody3D` + `move_and_slide()` | You write gravity yourself (3 lines). Template script ships with the node |
| Rigidbody / physics | `RigidBody3D` | Plates/tubs are RigidBody3D; grabbing = a joint or kinematic re-parent, we'll prototype both |
| Update loop dt | `delta` passed into `_process` | Physics at fixed 60Hz in `_physics_process` |
| Unity Input System / Enhanced Input | **Input Map** (Project Settings → actions) + `Input.is_action_pressed("grab")` | Very close to Enhanced Input actions, simpler |
| UGUI/UITK / UMG | **Control** nodes (a whole 2D UI node family) + themes | Excellent. Anchors/containers like UITK flexbox-ish |
| Addressables / asset pipeline | Everything is a file under `res://`, loaded with `load()`/`preload()` | No import GUIDs hell; text-based .tscn/.tres diffs beautifully in git |
| Editor | The editor IS a Godot game; ~100MB, opens in seconds, no domain reload ever | Iteration speed will genuinely spoil you |

## 2. Language choice: GDScript vs C#

You could write C# (Godot ships a .NET edition, real C# 12, works fine). **Recommendation: GDScript for Busser.** Reasons, honestly weighed:

- **Multiplayer**: the high-level MP API (`@rpc`, `MultiplayerSpawner`, `MultiplayerSynchronizer`) is designed GDScript-first; 95% of tutorials/examples/forum answers for Godot 4 multiplayer are GDScript. As first-timers, we want the well-lit path.
- **No build step**: edit script → ctrl+s → running game hot-reloads. C# requires a rebuild cycle.
- **Export**: C# cannot export to web; GDScript can (a web demo is great friendslop marketing).
- It's Python-shaped with optional static typing - `func grab(item: Dish) -> bool:`. **Always use typed GDScript**; it's faster at runtime and catches Unity-dev-brain mistakes. You'll be productive in an afternoon.
- Mixing is allowed later (C# for a hot inner loop) but we won't need it - the heavy lifting (physics, nav, rendering) is engine C++ anyway.

## 3. GDScript in 60 seconds (typed style we'll use)

```gdscript
class_name Dish
extends RigidBody3D

enum State { ON_TABLE_DIRTY, IN_TUB, AT_PIT, RACKED, WASHING, CLEAN_SHELF, ON_TABLE_SET }

signal state_changed(new_state: State)

@export var dish_type: DishType          # a custom Resource, like an SO
@export var wobble_factor: float = 1.0

var state: State = State.CLEAN_SHELF:
    set(value):                          # property setter, like C# properties
        state = value
        state_changed.emit(value)

func _ready() -> void:
    body_entered.connect(_on_body_entered)   # signal hookup

func _physics_process(delta: float) -> void:
    pass

@rpc("any_peer", "call_local", "reliable")   # networking is THIS easy to declare
func request_pickup(player_id: int) -> void:
    pass
```

Gotchas from C#: indentation is syntax; `null` checks via `if node:`; `$ChildName` is shorthand for `get_node("ChildName")`; `@onready var cam := $Camera3D` defers until _ready.

## 4. Multiplayer (the part we actually care about)

Godot 4's high-level multiplayer, host-as-server over **ENet** (UDP). Core pieces:

- `multiplayer.multiplayer_peer = ENetMultiplayerPeer` - host `create_server(port)`, client `create_client(ip, port)`.
- **`MultiplayerSpawner`** - node that auto-replicates scene instantiations from server to clients (players joining, guests spawning, dishes… though our dishes pre-exist, so mostly players/guests).
- **`MultiplayerSynchronizer`** - node that replicates chosen properties (transform, state enum) on a tick, with interpolation. Config is visual, in the inspector.
- **`@rpc` annotations** - per-function: who may call (`authority`/`any_peer`), where it runs (`call_local`/`call_remote`), channel + reliability.
- **Authority model**: every node has one authority (default: server). We keep it server-authoritative: clients send input/intent RPCs, server simulates, synchronizers push state down - matches the FBK architecture you already know.
- Physics for *held/thrown* items: authority simulates, clients see synced transforms. Do NOT try to sync full ragdoll physics for everything; sleeping dishes sync nothing.
- Later: Steam via GodotSteam (mature community module) for lobbies/relay - swap the peer, gameplay code unchanged.

## 5. Godot-specific practices we'll adopt day 1

1. **Scene = prefab discipline**: `scenes/props/dish.tscn`, `scenes/actors/busser.tscn`, `scenes/levels/diner.tscn`. Script attached to scene root, `class_name` for everything reusable.
2. **Resources as data** (FBK reusable-infra principle carries over): `DishType.tres`, `GuestArchetype.tres`, `ShiftConfig.tres` - designers/we tune in inspector, zero code changes.
3. **Signals up, calls down** - no `get_parent()` reach-arounds; decoupling comes free.
4. **Autoloads kept thin**: `Net.gd`, `GameState.gd`, `DishLedger.gd` only.
5. **Version control**: text scenes diff great. `.gitignore`: `.godot/` (the import cache - the whole folder), export builds. That's basically it. Godot + git is painless compared to Unity.
6. **Folders**: `res://scenes`, `res://scripts` (or co-located scripts next to scenes - we'll co-locate), `res://resources`, `res://assets` (models/audio/textures), `res://addons` (plugins).

## 6. First-week learning path (targeted, not generic)

1. Install **Godot 4.x stable, standard build** (not .NET) - single ~100MB exe, no installer.
2. 1 hr: official "Your first 3D game" feel-pass - just to touch editor, nodes, signals.
3. Build our own vertical slice immediately (best way to learn): FPS controller → physics grab → one table + one dish + state machine → ENet host/join with two windows on one PC (Godot runs multiple debug instances natively - brilliant for MP dev: Debug → "Run Multiple Instances → 2").
4. Bookmark: docs.godotengine.org - the class reference is built into the editor (F1), searchable offline.

## 7. Things that will feel wrong for a week (then great)

- No solution/project files; the folder IS the project (`project.godot`).
- One script per node, one class per file.
- The editor never blocks on compile; scripts hot-reload while the game runs.
- UI is nodes too - the pause menu is a scene like any other.
- 3D units are meters, +Y up, **-Z forward** (like Unity's flipped… just trust `Node3D.forward` idioms: `-transform.basis.z`).
