#!/bin/bash
# Find exported Lua functions that are never called from anywhere.
cd "$(git rev-parse --show-toplevel)"

found=0
for f in lua/todo-ai/*.lua; do
  mod=$(basename "$f" .lua)
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    # Count references outside the definition line
    refs=$(rg -c -g "*.lua" -g "*.vim" "\.$fn\b" lua/ plugin/ tests/ 2>/dev/null \
      | awk -F: '{s+=$2}END{print s+0}')
    # Subtract 1 for the definition itself
    refs=$((refs - 1))
    if [ "$refs" -le "0" ]; then
      echo "  DEAD: $mod.$fn"
      found=1
    fi
  done < <(sed -n 's/^function M\.\([a-zA-Z_]*\).*/\1/p' "$f")
done

if [ "$found" -eq "0" ]; then
  echo "  No dead code found. ✓"
fi
