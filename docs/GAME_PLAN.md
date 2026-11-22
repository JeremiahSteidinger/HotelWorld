# HotelWorld — Game Plan

## Context
HotelWorld is a hobby tycoon game for Windows and Mac, for personal play. You start with a small roadside motel and run it yourself, checking guests in and cleaning rooms. Every task takes time, and long lines or dirty rooms lead to bad reviews and discount requests. Profit pays for staff, and later for bigger hotels. Milestone 1 (the playable motel) is built; see the README for how to run it.

## Locked decisions
- **Engine:** Godot 4.3 (GDScript). **Look:** 2D isometric pixel art. **Owner tasks:** click to assign. The owner walks over and a progress bar runs.
- **Day length:** about 4 real minutes at 1x speed, with pause and 1x, 2x or 4x speed.
- **Owner:** can keep helping after staff are hired.
- **Modes:** campaign goals plus a sandbox. Bankruptcy ends the game in campaign mode. M1 ships one campaign goal plus the sandbox.
- **Guests:** archetypes (Budget Traveller, Family, Business) with different budgets, patience and stay lengths.
- **Rates:** one nightly rate per room type (M1 room types: Single, Double). No weekend or season pricing.
- **Staff:** wages only. A housekeeper or front desk clerk works at a fixed speed. Low pay relative to the market gives a small morale penalty that makes them quit sooner. No skill, training or shifts yet.
- **Finances:** cash, room revenue, wages and daily upkeep. No taxes, loans or mortgages (loans and mortgages come in phase 2).
- **Amenities:** roadmap only.
- **Tone:** light and humorous. Funny review text and guest quirks.
- **Platform:** Windows and macOS, personal use, no Steam.

## Roadmap (recorded in docs, not built now)
- **Phase 2:** loans and mortgages, a second property (mid-size hotel), maintenance staff, shifts.
- **Phase 3:** training and skills. Promotions: front desk clerk → front desk manager → general manager (managers automate decisions and give bonuses to their team).
- **Phase 4:** amenities (restaurant, spa and massage, pool and water park), free build mode, a map with multiple properties.

## Art approach
I can't paint hand-drawn art, but I can make clean pixel art in code. A Python/Pillow script (`tools/gen_art.py`) draws the isometric floor and wall tiles, room furniture (bed, desk), simple guest and worker sprites in colour variants, and the UI icons as PNGs. That gives a consistent, readable placeholder style. You can swap any PNG later (art you make, commission or download, such as the free CC0 Kenney packs) without touching code, because the sprites are only loaded by path.

## Project structure
```
project.godot
tools/gen_art.py                 # generates art/*.png
art/                             # tiles, sprites, icons (generated)
data/balance.json                # durations, patience, prices, wages, demand constants
scripts/sim/   game_clock.gd, economy.gd, demand.gd, reviews.gd, balance.gd   # pure logic (RefCounted)
scripts/entities/ guest.gd, room.gd, worker.gd, task.gd
scripts/managers/ task_manager.gd, guest_manager.gd, staff_manager.gd, save_manager.gd
scripts/ui/    hud.gd, rates_panel.gd, staff_panel.gd, daily_report.gd, reviews_panel.gd, popup_discount.gd
scenes/        main.tscn, motel.tscn, guest.tscn, worker.tscn, ui/*.tscn
tests/run_tests.gd               # unit tests for sim logic (no add-ons needed)
tools/sim_30_days.gd             # headless balance run
docs/GAME_PLAN.md                # updated with decisions + roadmap
```
The simulation (`sim/`, `entities/`) knows nothing about nodes. Scenes only show its state, so unit tests and a headless 30-day run both work.

## Core loop details
- **Rooms:** 6 rooms (4 Single, 2 Double). States: Clean → Occupied → Dirty → Cleaning → Clean.
- **Guest flow:** arrive → join the desk queue (patience drains) → check-in task → walk to the room → stay N nights → check-out task (morning) → review. Leaves angry if patience runs out or no clean room is ready.
- **Mood → review:** stars come from mood. The review text is picked from humorous templates by cause (long wait, dirty room, overpriced, great value). The rating is a rolling average of the last 20 reviews.
- **Discount requests:** if mood falls below a threshold, a popup asks for 10–30% off. Accept it and lose money but improve the review. Refuse it and the review gets worse.
- **Demand:** daily arrivals = base × rating factor × price factor (rate against the archetype's budget), capped by room count.
- **Staff:** the hire panel shows candidates and the asking wage. Each staff member grabs tasks for their role from the task queue. Wages are paid at midnight.
- **Campaign goal (M1):** reach $9,000 cash within 30 days (start with $1,500) to "buy the next property". You lose if cash < 0 for 3 days in a row.
- **Save and load:** a text save file in `user://` (Godot's per-user data folder).

## Build steps
1. Scaffold the Godot 4.3 project and `.gitignore`.
2. `gen_art.py` → art PNGs. Isometric TileMap of the motel, front desk, camera pan and zoom.
3. Clock, speed controls, HUD (cash, day and time, rating, speed).
4. Rooms, guest spawning, desk queue, NavigationAgent2D movement.
5. Task system plus click to assign for the owner, with a progress bar.
6. Mood, patience, reviews and rating, discount popup, reviews panel.
7. Economy: rate panel per room type, upkeep, end-of-day report.
8. Staff hire and fire panel (wages only), automatic task pickup.
9. Demand model, `balance.json`, save and load, campaign goal and bankruptcy, sandbox toggle.
10. Tests, headless balance tuning, screenshots, update docs, commit and push.

## Playing on Windows and Mac
- **Easiest on both:** install Godot 4.3 from godotengine.org (one app, the same on Windows and Mac), clone the repo, open `project.godot` and press F5.
- **Cross-platform input from day one:** camera pan works with the mouse, WASD or trackpad drag. Zoom works with the scroll wheel, a trackpad pinch or the +/- keys. Nothing needs right-click, which is awkward on a Mac trackpad. The UI scales with the window, so it looks sharp on Retina screens. Saves go to `user://`, which works on both.
- **Standalone builds (optional, later):** use `export_presets.cfg` for Windows (`.exe`) and macOS (`.app`), with export templates (an extra ~1 GB download). The unsigned Mac app shows a Gatekeeper warning on first launch. Right-click → Open gets past it. Signing needs a $99/yr Apple account, which isn't needed for personal use.

## Verification
- Unit tests: `godot --headless --path . --script res://tests/run_tests.gd`.
- `godot --headless --script tools/sim_30_days.gd` prints daily cash and rating for a few strategies (no staff, 1 housekeeper, overpriced) and checks the balance: not bankrupt by default, goal reachable but not trivial.
- Launch with xvfb and lavapipe, script clicks (check in a guest, clean a room, let a queue build, hire a housekeeper, change the rate) and capture screenshots to confirm it works.
- Commit to `claude/vigilant-gates-i52wd1` and push.
