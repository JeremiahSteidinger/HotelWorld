# HotelWorld — Game Plan

## Context
HotelWorld is a hobby tycoon game for Windows and Mac, for personal play. You start with a small roadside motel and run it yourself, checking guests in and cleaning rooms. Every task takes time, and long lines or dirty rooms lead to bad reviews and discount requests. Profit pays for staff, and later for bigger hotels. Milestone 1 (the playable motel) and Phase 2 (the hotel, bank, shifts and maintenance) are built; see the README for how to run it.

## Locked decisions
- **Engine:** Godot 4.3 (GDScript). **Look:** 2D isometric pixel art. **Owner tasks:** click to assign. The owner walks over and a progress bar runs.
- **Day length:** about 4 real minutes at 1x speed, with pause and 1x, 2x or 4x speed.
- **Owner:** can keep helping after staff are hired.
- **Modes:** campaign goals plus a sandbox. Bankruptcy ends the game in campaign mode. M1 ships one campaign goal plus the sandbox.
- **Guests:** archetypes (Budget Traveller, Family, Business) with different budgets, patience and stay lengths.
- **Rates:** one nightly rate per room type (M1 room types: Single, Double). No weekend or season pricing.
- **Staff:** wages and shifts (phase 2). A housekeeper, front desk clerk or maintenance tech works at a fixed speed. Low pay relative to the market gives a small morale penalty that makes them quit sooner. No skill or training yet.
- **Finances:** cash, room revenue, wages and daily upkeep. Loans and mortgages since phase 2. No taxes.
- **Amenities:** roadmap only.
- **Tone:** light and humorous. Funny review text and guest quirks.
- **Platform:** Windows and macOS, personal use, no Steam.

## Phase 2 (built)
Playtest of M1: chapter 1 was won on day 24 of 30, which matches the bots (the solo bot wins on days 22–25), so its balance is unchanged.
- **Structure:** the simulation is split into `Game` (one clock, one bank account, loans, campaign, the owner's travel) and `Property` (map, rooms, guests, staff, reviews, rates). The Game ticks every property each step; each property pays its own wages and upkeep at midnight, then the bank takes its payments.
- **Second property:** the Maple Grove Hotel. It has 14 rooms (6 Queen, 5 King, 3 Suite), a 6×5 lobby with a three-person desk, an indoor hall with rooms on both sides (front-row rooms have cut-away walls so the hall stays visible), and a bigger parking lot. It attracts more business guests, plus a new archetype: Couples on a Getaway, who book suites. It costs $40,000, is rated 2.6 when you buy it, and 4 rooms are out of order.
- **Owner travel:** the owner is at one property at a time. An order at the other property (click a room, the desk, or "Drive to...") makes them walk to the car and drive over (40 game minutes) first. The view (tabs, Tab key) is separate from where the owner is.
- **Maintenance:** each check-out has a chance to break something (4% at the motel, 10% at the hotel), with funny log text. Broken rooms can't be rented. A maintenance tech fixes one in 30 minutes; the owner takes 60. Parts cost $15.
- **Shifts:** Day 7–15, Evening 15–23, Night 23–7. Staff arrive at the start of their shift, finish the guest or room they're on, then go home. A wage covers one shift per day. New clerks start on Evening (check-ins), housekeepers and techs on Day. The Staff window shows coverage per shift and warns when the desk has gaps.
- **Bank:** business loans up to 50% of property value minus existing debt, at 0.4%/day over 30 days, with amortized daily payments and early repayment. Mortgage: 20% down, then 0.1%/day over 150 days (about $229/day for the hotel).
- **Campaign:** chapter 1 is unchanged except that the goal counts savings (cash minus loans), so borrowing can't win it. Chapter 2: own the hotel and reach $100,000 net worth by day 100. The pro bot wins chapter 2 around days 81–85, and a human juggling two properties will have less slack. Sandbox: the hotel is for sale whenever you have the down payment.
- **Saves:** version 2. Version 1 saves are converted on load.

## Roadmap (recorded in docs, not built now)
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
