#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/homeboi.sh"

if [[ ! -x "$TARGET_SCRIPT" ]]; then
  chmod +x "$TARGET_SCRIPT" 2>/dev/null || true
fi

install_global() {
  local dest="/usr/local/bin/homeboi"
  if command -v sudo >/dev/null 2>&1; then
    sudo ln -sf "$TARGET_SCRIPT" "$dest"
    echo "✓ Installed: $dest -> $TARGET_SCRIPT"
    return 0
  fi
  return 1
}

install_user_local() {
  local user_bin="${HOME}/.local/bin"
  local dest="${user_bin}/homeboi"
  mkdir -p "$user_bin"
  ln -sf "$TARGET_SCRIPT" "$dest"
  echo "✓ Installed: $dest -> $TARGET_SCRIPT"

  if ! command -v homeboi >/dev/null 2>&1; then
    echo
    echo "⚠ '${user_bin}' is not on your PATH."
    echo "Add this to your shell profile (e.g. ~/.bashrc or ~/.zshrc):"
    echo "  export PATH=\"${user_bin}:\$PATH\""
  fi
}

echo "Installing Homeboi command..."

if install_global 2>/dev/null; then
  :
else
  echo "ℹ Could not install to /usr/local/bin (sudo required). Installing user-local instead."
  install_user_local
fi

echo
echo "Run: homeboi"
