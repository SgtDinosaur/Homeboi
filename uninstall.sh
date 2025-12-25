#!/usr/bin/env bash
set -euo pipefail

removed_any=false

remove_if_exists() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -f "$path"
    echo "✓ Removed: $path"
    removed_any=true
  fi
}

remove_if_exists "${HOME}/.local/bin/homeboi"

if command -v sudo >/dev/null 2>&1; then
  if sudo test -e /usr/local/bin/homeboi 2>/dev/null; then
    sudo rm -f /usr/local/bin/homeboi
    echo "✓ Removed: /usr/local/bin/homeboi"
    removed_any=true
  fi
fi

if [[ "$removed_any" == "false" ]]; then
  echo "No Homeboi command found to remove."
fi

echo
echo "Note: this does not delete your stack/configs. Use Homeboi → Remove Stack for that."
