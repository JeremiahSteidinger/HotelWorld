# HotelWorld — Plan

## Context
HotelWorld is a new PC tycoon game about building and running hotels and resorts. The player starts with a small roadside motel and runs it alone: checking guests in and cleaning rooms. Every task takes time. Long lines or dirty rooms upset guests, and upset guests leave bad reviews and ask for discounts. Profits let the player hire staff, set room rates and wages, and later open larger hotels with amenities such as a restaurant, a spa or massages, and a water park. The repo (`/home/user/HotelWorld`) is empty.

**Decisions made:** Godot 4 (GDScript), 2D isometric pixel art, point-and-click task assignment (click a guest or room, the owner walks there and works on a timer). The first milestone is a **playable motel prototype**.

## Core design pillars
1. **Time is the resource.** Each action has a duration and the player cannot be everywhere at once. Pressure comes from queues and arrival timing.
2. **Guest satisfaction drives the economy.** Satisfaction leads to reviews, reviews set the star rating, and the star rating sets demand and the prices guests will accept.
3. **Hands-on to hands-off.** The player begins as the only worker. Hiring staff frees them to manage, and management (rates, pay, upgrades) becomes the core game.
4. **Grow your property.** Motel → mid-size hotel → resort, each step adding new systems (amenities, departments).

## Core simulation model (milestone 1)
- **Clock:** game minutes and days, with pause and 1x, 2x or 4x speed. Guests arrive in waves (afternoon check-in peak, morning check-out).
- **Guest:** has patience, a budget, a stay length, a party size and a mood (0–100). Mood drops while waiting in line, for a dirty or unready room, or when the price is above their budget. It rises with fast service and a clean room. At checkout, mood becomes a 1–5 star review, sometimes with a complaint or a discount request (accept it and lose money, or refuse it and get a worse review).
- **Room states:** Vacant-Clean → Occupied → Vacant-Dirty → Cleaning → Vacant-Clean. Rooms can also be under maintenance (broken AC, for example).
- **Tasks:** check-in, check-out, clean room, fix item. Each has a duration and is done by a worker (the owner or staff) through a task queue. Staff pick tasks automatically, depending on their role.
- **Staff:** role (front desk or housekeeping, with maintenance later), wage, skill (speeds up tasks), morale (low pay → slower work → they quit). Hire and fire through a simple panel.
- **Economy:** cash, nightly room rate set by the player, wages paid daily, upkeep costs. A daily report shows revenue, expenses and average rating.
- **Demand:** daily arrivals = f(star rating, price against what the market expects, room count).
- **Win/lose (prototype):** reach a cash goal, such as enough to "buy the next property", or go bankrupt.

## Project structure (Godot 4)
```
project.godot
scenes/   main.tscn, motel.tscn (TileMap isometric), guest.tscn, worker.tscn, ui/*.tscn
scripts/
  sim/      game_clock.gd, economy.gd, demand.gd, review_system.gd   (pure logic, no nodes where possible)
  entities/ guest.gd, room.gd, worker.gd, task.gd
  managers/ task_manager.gd, guest_manager.gd, staff_manager.gd
  ui/       hud.gd, rates_panel.gd, staff_panel.gd, daily_report.gd, reviews_panel.gd
data/       balance.tres / JSON (prices, durations, patience, wages: tunable without code)
art/        placeholder isometric tiles + sprites
tests/      GUT unit tests for sim/ logic
```
Keep the simulation (`sim/`, `entities/`) separate from rendering so the balance can be unit-tested and a headless "fast-forward 30 days" run is possible.

## Build steps (milestone 1)
1. Godot project scaffold, isometric TileMap of a 6-room motel, front desk, camera pan and zoom.
2. Game clock plus speed controls and the HUD (cash, time, rating).
3. Rooms and the room state machine. Guests spawn, queue at the desk, and pathfind with NavigationAgent2D.
4. Task system: click a guest or room, the owner walks there and a progress bar fills while the task runs.
5. Guest mood, patience leaving, reviews and the star rating, plus discount-request popups.
6. Economy: room rate slider, daily costs, end-of-day report.
7. Hiring: front desk and housekeeper staff with wages, skill and morale. They take tasks automatically.
8. Demand model tied to rating and price, data-driven balance file, save and load (JSON).
9. Placeholder art pass and a basic sound pass, then a playtest and tuning.

## Later milestones (not in this build)
- M2: buy a second property (mid-size hotel), maintenance staff, a first amenity (restaurant).
- M3: build mode (place rooms and furniture), multiple properties managed at once, marketing.
- M4: resort tier with a spa or massage, a pool or water park, events, seasons, competitors.

## Open questions for you (do not block M1; defaults in brackets)
**Gameplay & feel**
1. How long should a game day last in real time at 1x speed? [~4 minutes]
2. Should the owner keep working after staff are hired, or move into a pure manager role? [optional: they can still help]
3. Can the player lose (bankruptcy), or is it a sandbox? Is there a campaign with scenarios, or open-ended play? [both: a campaign of goals plus a sandbox]
4. How detailed should guests be: anonymous types (budget traveller, family, business) or named guests with stories? [types]

**Management depth**
5. Room rates: one rate per room type, or dynamic pricing by day and season and online-travel-agency (OTA) fees? [per type, plus weekend/season modifiers later]
6. Staff: just wages, or also shifts, training, benefits, unions? [wages, skill, morale, shifts in M2]
7. Finances: loans, mortgages, taxes, a stock market? [loans in M2]

**Expansion**
8. Do players build the hotel layout themselves (room by room), or buy pre-made buildings and upgrade them? [pre-made in M1–M2, free build in M3]
9. Is it one location that grows, or a map with multiple cities and a hotel chain? [a map with properties]
10. Which amenities are must-haves, and do any have their own mini-management (restaurant menus, water park rides)? [restaurant, spa and pool first, with light sub-management]

**Presentation & business**
11. Art: will you make or commission it, or should I use free placeholder asset packs? [placeholders]
12. Target platform and store (Steam? Mac/Linux too?) and minimum PC specs? [Windows on Steam first]
13. Is this a solo hobby project, or a commercial one with a team and a timeline? (Affects tooling and scope.)
14. Tone: realistic, or cartoony and humorous (funny reviews, odd guests)? [light and humorous]

## Verification
- Unit tests (GUT) for the guest mood, review, economy and demand formulas: `godot --headless -s addons/gut/gut_cmdln.gd`.
- Headless 30-day simulation script that prints the daily cash and rating, to check the balance (not bankrupt by default and not trivially rich).
- Run the game, check in a guest, clean a room, let a line build to see guests leave and bad reviews arrive, hire a housekeeper, change the rate and see demand respond. Capture screenshots.
- Commit to `claude/vigilant-gates-i52wd1` and push.
