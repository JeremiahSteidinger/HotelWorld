#!/usr/bin/env bash
# Parse-check every GDScript file. Usage: tools/check_scripts.sh /path/to/godot
G="${1:-godot}"
cd "$(dirname "$0")/.."
status=0
for f in $(find scripts tools tests -name '*.gd' 2>/dev/null); do
  out=$(timeout 30 "$G" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|error\(" -A1)
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; status=1; fi
done
exit $status
