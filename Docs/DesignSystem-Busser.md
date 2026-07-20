# Busser - Visual Design System (from Figma, 2026-07-18)

Source of truth for the UI restyle pass. Sharp, industrial diner-punk: **hard
corners (radius 0)**, dark slate panels, hazard-yellow primary, condensed caps
for headings, mono-ish tracked-out labels.

## Palette (Figma export)

| Token | Hex | Use |
|---|---|---|
| background | `#1F2937` | app/world backdrop (slate-800) |
| foreground | `#F9FAFB` | primary text (near-white) |
| card / popover / muted / sidebar | `#111827` | panels, HUD boxes (slate-900) |
| primary / accent / ring | `#FACC15` | CTA, highlights, focus, star fill (yellow-400) |
| primary-foreground | `#1F2937` | text ON yellow |
| secondary / input-bg / switch | `#374151` | inputs, secondary buttons (slate-700) |
| muted-foreground | `#6B7280` | sub-labels, hints (gray-500) |
| destructive | `#DC2626` | alarms, "smashed", fees, 86'd (red-600) |
| border | `rgba(249,250,251,0.12)` | hairline separators |
| chart-2 | `#4ade80` | good/green (covers, ready) |
| chart-4 | `#fb923c` | warn/orange |
| chart-5 | `#60a5fa` | info/blue |

- **radius: 0rem** everywhere. No rounded corners.
- font-weight: normal 400, medium 600. Headings tracked-out uppercase.

## Mockups (in repo: `Figma/main-menu.png`, `Figma/player-hud.png`, `Figma/shift-report.png`)

1. **IN-GAME HUD** - top-left: crew list (name + colored status bar per player,
   green=CHEF_MIKE ready / yellow=bussergirl99). Top-right: `SHIFT TRACKER //
   LUNCH WAVE` card - clock + yellow progress bar + `39m`, `$342.50 / $500`
   green, 3/5 yellow stars. Bottom-center: vertical **WOBBLE** meter (green fill)
   next to a `PLATES CARRIED 7 / 10  ⚠ HEAVY` card (red HEAVY). Bottom-right:
   `⚠ STATUS ALARM - NO CLEAN PLATES AT THE PASS` in red. Crosshair = white dot+ticks.
2. **SHIFT REPORT** - torn-receipt card (cream `#F5F0E6`-ish on navy). `SHIFT
   OVER` boxed header, `REPORT CARD`, location/date line. Two columns: ✓ THE GOOD
   (Covers Seated 47, Tips Earned $124.50 green, Cleanliness Bonus +12%) / ✗ THE
   CHAOS (Dishes Smashed 3 + red -$18 fee, Guest Walkouts 2, Near-Fatal Slips 7).
   Star rating + verdict `PASSABLE SHIFT`. Earnings math to NET. Two buttons:
   yellow `CLOCK IN NEXT SHIFT`, slate `RETURN TO BREAKROOM`.
3. **MAIN MENU** - giant white `BUSSER` wordmark, yellow underline, tagline
   `FIRST-PERSON // CO-OP // DINER CHAOS // SMT GAMES`. Left nav: CLOCK IN (Play),
   SHIFT SETTINGS (Lobby/Matchmaking), EMPLOYEE HANDBOOK (Tutorial), LOCKER ROOM
   (Cosmetics), CLOCK OUT (Quit) - each with gray sub-label, yellow on hover/active.
   Right: `CURRENT SHIFT CREW 2/4` lobby panel (numbered slots, READY/JOINING/OPEN,
   lobby code `XK-447-R`). Blurred diner behind. Footer: SMT GAMES // Draft 0.1.

## Naming voice (diegetic, keep it)
Clock In = Play, Shift Settings = lobby, Employee Handbook = tutorial, Locker Room
= cosmetics, Clock Out = quit, Breakroom = main menu. 86'd = fail. Covers = served.

## Godot mapping notes (for the UITK-equivalent - Godot Control themes)
Build a Godot `Theme` resource with these colors, or a `theme_type_variation`
set. Current HUD is code-driven Labels/ColorRects in diner.tscn + hud.gd; the
menu is main_menu.tscn. Restyle target: one shared `.tres` theme + panel styles
(StyleBoxFlat, corner_radius 0, bg #111827, border 1px rgba white .12).
