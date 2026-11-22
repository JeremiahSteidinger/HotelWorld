# HotelWorld

A hobby tycoon game about building a hotel empire, starting with one roadside motel.
Made with **Godot 4.3** (GDScript) and 2D isometric pixel art.

You run the motel yourself at first: check guests in at the front desk and clean rooms
after they check out. Everything takes time. If the line gets long or a room isn't clean
when a guest arrives, they get upset, ask for discounts and leave bad reviews. Your
rating decides how many guests come and how much they'll pay. Once you can afford it,
hire a front desk clerk and housekeepers, and set room rates and wages.

![The motel](docs/screenshots/day2_checkout.png)

See [docs/GAME_PLAN.md](docs/GAME_PLAN.md) for the design and the roadmap (loans and
mortgages, bigger hotels, shifts, training, promotions, amenities).

## Play it (Windows or Mac)

1. Download **Godot 4.3** (standard version, not .NET) from
   https://godotengine.org/download/archive/4.3-stable/. It's a single app, no installer.
2. Download or clone this repository.
3. Open Godot, click **Import**, pick this folder's `project.godot`, then press **F5**
   (or the ▶ button) to play.

The first time you open the project, Godot spends a few seconds importing the art.

## How to play

- Guests line up at the front desk. Someone must be **at the desk** to check them in or out.
- When guests check out, their room is **dirty**. Click a dirty room to go clean it.
- You can queue several jobs: they happen in order (see the panel bottom-left).
- Guests whose room isn't ready wait in the lobby and get grumpy. Waiting too long
  makes them leave or demand a refund.
- **Rates**: set the nightly price per room type. **Staff**: hire, set wages, let go.
  **Reviews**: what guests think. **Report**: yesterday's numbers.
- Campaign: turn $1,500 into $9,000 within 30 days. Go broke three nights in a row and
  it's over. Sandbox: no goal, no bankruptcy.

| Control | Action |
|---|---|
| Left click a room | Clean it (if dirty) |
| Left click the lobby, the line or a guest | Work the front desk |
| F | Go to the front desk |
| Drag, WASD or arrow keys | Move the camera |
| Mouse wheel, trackpad pinch or + / - | Zoom |
| Space | Pause |
| 1 / 2 / 3 | Speed 1x / 2x / 4x |
| Esc | Close a window |

The game auto-pauses while a window (report, discount request, staff, etc.) is open.

## Project layout

```
scenes/main.tscn        entry scene
scripts/main.gd         camera, input, speed, save/load
scripts/sim/            the simulation (pure logic, no nodes): guests, rooms, staff, money
scripts/view/           draws the world from the simulation state
scripts/ui/ui.gd        HUD and management windows
data/balance.json       all tuning numbers (prices, patience, wages, durations, demand)
art/                    generated pixel art (replace any PNG with your own, same size)
tools/gen_art.py        regenerates the art (python3 + Pillow)
tools/sim_30_days.gd    headless balance check with bot players
tests/run_tests.gd      unit tests
```

## Tweaking and testing

Most tuning is in `data/balance.json`: no code changes needed.

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

```bash
godot --headless --path . --script res://tools/sim_30_days.gd
```

```bash
python3 tools/gen_art.py
```
