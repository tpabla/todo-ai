#!/bin/bash
# Find potentially dead Lua functions (public API only — skips _private functions)
cd "$(dirname "$0")/.." || exit 1

echo "Checking for dead Lua functions..."

for file in lua/todo-ai/*.lua; do
  module=$(basename "$file" .lua)
  # Only check public functions (not prefixed with _)
  grep -o 'function M\.[a-zA-Z_]*' "$file" | sed 's/function M\.//' | while read -r func; do
    case "$func" in _*) continue ;; esac
    count=$(grep -r --include='*.lua' --include='*.vim' --include='*.ts' \
      "$func" lua/ plugin/ extension/ tests/ 2>/dev/null \
      | grep -v "^${file}:" | grep -cv "^[[:space:]]*--")
    if [ "$count" -eq 0 ]; then
      echo "  DEAD: ${module}.${func}"
    fi
  done
done
