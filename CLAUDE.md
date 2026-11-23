# Working on HotelWorld

## Branches
- `develop` is where the owner tests. Every finished change must end up merged into
  `develop` and pushed. Work on your session branch, then merge it into `develop`.
- `main` only moves forward from `develop` when the owner asks.

## Before merging into develop, make sure it runs (Godot 4.3)
```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
tools/check_scripts.sh godot
godot --headless --path . --quit-after 600
```
Godot 4.3 for Linux: https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
Discard the `art/*.import` churn the import step leaves behind (`git checkout -- art/`).
For a visual check: `xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tools/capture.gd -- <out_dir>`
